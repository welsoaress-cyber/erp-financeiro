-- Testes da migration 0116 (vencimento de cobrança de contrato em lote). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Venc Lote', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco Venc Lote') conta;

-- T1: escopo 'futuras' — edita o vencimento desta fatura (atualizar_lancamento normal) e
-- cascateia: próximas já geradas (ainda previstas) acompanham; contrato também atualiza.
-- Já efetivada (passado) e outro contrato não são tocados.
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; l1 public.lancamentos%rowtype; l2 public.lancamentos%rowtype; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'VENC LOTE', 'venc-lote') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Venc Lote') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Venc Lote', 35) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 35, 'mensal', date '2026-08-29', 29) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct; -- agosto, 29/08
  perform public.efetivar_lancamento(l0.id, date '2026-08-29'); -- paga em dia, não reancora nada
  perform public.gerar_faturamento_agora(date '2026-10-31'); -- gera setembro e outubro, previstos, 29/09 e 29/10

  select * into l1 from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-09-29';
  select * into l2 from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-10-29';

  -- cliente pede pra mudar o vencimento de setembro pro dia 5, e que valha pras próximas também
  perform public.atualizar_lancamento(l1.id, l1.descricao, l1.valor, l1.data_competencia, date '2026-09-05', null,
    l1.conta_id, null, l1.categoria_id, null, l1.negocio_id, l1.pessoa_id, l1.contrato_id, false, null, null, null);
  perform public.cascatear_vencimento_contrato(l1.id, 'futuras');

  assert (select data_vencimento from public.lancamentos where id = l1.id) = date '2026-09-05', 'T1 setembro (esta) no dia 5';
  assert (select data_vencimento from public.lancamentos where id = l2.id) = date '2026-10-05', 'T1 outubro (futura já gerada) cascateou pro dia 5';
  assert (select dia_vencimento from public.contratos where id = v_ct) = 5, 'T1 contrato também pro dia 5 (próximas a gerar)';
  assert (select data_vencimento from public.lancamentos where id = l0.id) = date '2026-08-29', 'T1 agosto (já paga) intocada com escopo futuras';
end $$;

-- T2: escopo 'todas' — também corrige o vencimento das já efetivadas (sem mexer em saldo/movimento)
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; l1 public.lancamentos%rowtype;
  saldo_antes numeric; saldo_depois numeric; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'VENC LOTE TODAS', 'venc-lote-todas') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Venc Lote Todas') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Venc Lote Todas', 35) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 35, 'mensal', date '2026-08-10', 10) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct; -- agosto, 10/08
  perform public.efetivar_lancamento(l0.id, date '2026-08-10');
  perform public.gerar_faturamento_agora(date '2026-09-30');
  select * into l1 from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-09-10';

  select saldo into saldo_antes from public.vw_saldo_contas where id = v.conta;
  perform public.atualizar_lancamento(l1.id, l1.descricao, l1.valor, l1.data_competencia, date '2026-09-20', null,
    l1.conta_id, null, l1.categoria_id, null, l1.negocio_id, l1.pessoa_id, l1.contrato_id, false, null, null, null);
  perform public.cascatear_vencimento_contrato(l1.id, 'todas');

  assert (select data_vencimento from public.lancamentos where id = l0.id) = date '2026-08-20', 'T2 agosto (já paga) também corrigida com escopo todas';
  select saldo into saldo_depois from public.vw_saldo_contas where id = v.conta;
  assert saldo_depois = saldo_antes, 'T2 saldo intocado (só data, não valor)';
end $$;

-- T3: não vale pra lançamento sem contrato
do $$ declare v r%rowtype; v_cat uuid; l public.lancamentos%rowtype; falhou boolean; begin
  select * into v from r;
  select id into v_cat from public.categorias where organizacao_id = v.org and tipo = 'despesa' limit 1;
  l := public.criar_lancamento('despesa', 'Avulso', 20, current_date, current_date, null, v.conta, null, v_cat);
  falhou := false;
  begin perform public.cascatear_vencimento_contrato(l.id, 'futuras'); exception when check_violation then falhou := true; end;
  assert falhou, 'T3 lançamento sem contrato recusado';
end $$;

rollback;
\echo OK
