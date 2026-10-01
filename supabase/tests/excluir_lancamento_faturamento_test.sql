-- Testes da migration 0118 (excluir_lancamento barra cobrança de contrato). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Excluir Faturamento', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco Excluir Faturamento') conta;

-- T1: lançamento avulso (origem manual) continua podendo ser excluído
do $$ declare v r%rowtype; v_cat uuid; l public.lancamentos%rowtype; begin
  select * into v from r;
  select id into v_cat from public.categorias where organizacao_id = v.org and tipo = 'despesa' limit 1;
  l := public.criar_lancamento('despesa', 'Avulso Excluir', 20, current_date, current_date, null, v.conta, null, v_cat);
  perform public.excluir_lancamento(l.id);
  assert not exists (select 1 from public.lancamentos where id = l.id), 'T1 avulso excluído normalmente';
end $$;

-- T2: cobrança de contrato (origem faturamento) recusa exclusão com mensagem clara, não o erro de FK
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; falhou boolean; v_msg text; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'EXCLUIR FATURAMENTO', 'excluir-faturamento') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Excluir Faturamento') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Excluir Faturamento', 50) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 50, 'mensal', current_date, 10) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct;
  assert l0.origem = 'faturamento', 'T2 pré-condição: cobrança do contrato é origem faturamento';
  falhou := false;
  begin
    perform public.excluir_lancamento(l0.id);
  exception when check_violation then
    falhou := true; get stacked diagnostics v_msg = message_text;
  end;
  assert falhou, 'T2 exclusão de cobrança de contrato é recusada';
  assert v_msg ilike '%Cancelar%', 'T2 mensagem orienta a usar Cancelar';
  assert exists (select 1 from public.lancamentos where id = l0.id), 'T2 lançamento continua existindo';
end $$;

rollback;
\echo OK
