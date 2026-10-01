-- Testes da migration 0117 (encerrar contrato cancela cobranças em aberto). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Encerrar Contrato', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco Encerrar Contrato') conta;

-- T1: sem p_cancelar_pendencias — encerra normalmente, lançamentos previstos continuam intocados
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'ENCERRAR SEM', 'encerrar-sem') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Encerrar Sem') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Encerrar Sem', 40) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 40, 'mensal', date '2026-08-10', 10) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct;
  perform public.encerrar_contrato(v_ct, current_date, false);
  assert (select status from public.contratos where id = v_ct) = 'encerrado', 'T1 contrato encerrado';
  assert (select status from public.lancamentos where id = l0.id) = 'previsto', 'T1 sem opt-in: lançamento continua previsto';
end $$;

-- T2: com p_cancelar_pendencias — futura (ainda não vencida) cancela como "contrato encerrado";
-- vencida antes da data de encerramento cancela como "perda"; já efetivada não é tocada.
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid;
  l_paga public.lancamentos%rowtype; l_vencida public.lancamentos%rowtype; l_futura public.lancamentos%rowtype; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'ENCERRAR COM', 'encerrar-com') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Encerrar Com') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Encerrar Com', 40) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 40, 'mensal', date '2026-06-10', 10) returning id into v_ct;
  select * into l_paga from public.lancamentos where contrato_id = v_ct; -- junho, paga
  perform public.efetivar_lancamento(l_paga.id, date '2026-06-10');
  perform public.gerar_faturamento_agora(date '2026-08-31'); -- gera julho (vencida) e agosto (futura, se encerrar em julho)
  select * into l_vencida from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-07-10';
  select * into l_futura from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-08-10';

  perform public.encerrar_contrato(v_ct, date '2026-07-20', true); -- encerra em 20/07: julho (venc. 10/07) já vencida, agosto ainda não

  assert (select status from public.lancamentos where id = l_paga.id) = 'efetivado', 'T2 já paga não é tocada';
  assert (select status from public.lancamentos where id = l_vencida.id) = 'cancelado', 'T2 vencida é cancelada';
  assert (select motivo_cancelamento from public.lancamentos where id = l_vencida.id) ilike 'Perda%', 'T2 vencida entra como perda';
  assert (select status from public.lancamentos where id = l_futura.id) = 'cancelado', 'T2 futura é cancelada';
  assert (select motivo_cancelamento from public.lancamentos where id = l_futura.id) not ilike 'Perda%', 'T2 futura não é perda, só cancelamento normal';
end $$;

-- T3: contrato já encerrado não pode ser encerrado de novo
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; falhou boolean; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'ENCERRAR DUAS', 'encerrar-duas') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Encerrar Duas') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Encerrar Duas', 40) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 40, 'mensal', date '2026-08-10', 10) returning id into v_ct;
  perform public.encerrar_contrato(v_ct, current_date, false);
  falhou := false;
  begin perform public.encerrar_contrato(v_ct, current_date, false); exception when check_violation then falhou := true; end;
  assert falhou, 'T3 contrato já encerrado recusa novo encerramento';
end $$;

rollback;
\echo OK
