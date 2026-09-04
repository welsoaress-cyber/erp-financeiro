-- Testes da migration 0034 (pagamento atrasado reancora vencimentos). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Reanc', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco Reanc') conta, (select id from public.categorias where nome='Moradia') moradia;

-- T1: fixa vencida 30/08, paga 04/09 → cadeia prevista vira 04/10, 04/11, 04/12
do $$ declare v r%rowtype; l1 public.lancamentos; v_datas date[]; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'João Servidor', 50, date '2026-08-30', date '2026-08-30', null, v.conta, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  perform public.projetar_lancamento(l1.id, 3); -- 30/09, 30/10, 30/11
  perform public.efetivar_lancamento(l1.id, date '2026-09-04');
  select array_agg(data_vencimento order by parcela_atual) into v_datas
    from public.lancamentos where descricao = 'João Servidor' and status = 'previsto';
  assert v_datas = array[date '2026-10-04', date '2026-11-04', date '2026-12-04'], 'T1 reancorado em 04: ' || v_datas::text;
end $$;

-- T2: pago em dia (ou adiantado) não muda nada
do $$ declare v r%rowtype; l1 public.lancamentos; v_datas date[]; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Em Dia', 50, date '2026-09-10', date '2026-09-10', null, v.conta, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  perform public.projetar_lancamento(l1.id, 2);
  perform public.efetivar_lancamento(l1.id, date '2026-09-10');
  select array_agg(data_vencimento order by parcela_atual) into v_datas
    from public.lancamentos where descricao = 'Em Dia' and status = 'previsto';
  assert v_datas = array[date '2026-10-10', date '2026-11-10'], 'T2 sem mudança: ' || v_datas::text;
end $$;

-- T3: cobrança de contrato paga atrasada muda o dia_vencimento do contrato
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct public.contratos%rowtype; l public.lancamentos%rowtype; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'REANC TESTE', 'reanc-teste') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where nome='Salário' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Reanc') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Reanc', 40) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 40, 'mensal', date '2026-08-30', 30) returning id into v_ct;
  select l2.* into l from public.lancamentos l2 where l2.contrato_id = v_ct.id; -- 1ª cobrança (30/08), gerada ao criar
  perform public.efetivar_lancamento(l.id, date '2026-09-06');
  select c.* into v_ct from public.contratos c where c.id = v_ct.id;
  assert v_ct.dia_vencimento = 6, 'T3 contrato reancorado no dia 6, veio ' || v_ct.dia_vencimento;
end $$;

rollback;
\echo OK
