-- Testes da migration 0120 (reancoragem diferente pra negócio pré-pago). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Reanc Prepago', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco Reanc Prepago') conta;

-- T1: negócio pré-pago (ex.: Servidor Toptv) — vencia dia 28, cliente paga dia 01 do mês
-- seguinte. As faturas futuras JÁ GERADAS encadeiam a partir do pagamento + 1 período
-- (não do dia do mês): setembro = pagamento + 1 mês, outubro = setembro + 1 mês.
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug, ciclo_prepago) values (v.org, 'SERVIDOR PREPAGO', 'servidor-prepago', true) returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Servidor Prepago') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Servidor Prepago', 35) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 35, 'mensal', date '2026-08-28', 28) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct; -- agosto, 28/08

  -- faturamento adiantado: setembro (25/09) e outubro (28/10) já geradas, previstas
  perform public.gerar_faturamento_agora(date '2026-10-31');
  assert (select count(*) from public.lancamentos where contrato_id = v_ct and status = 'previsto' and id <> l0.id) = 2, 'T1 set/out geradas e previstas';

  -- cliente só paga agosto em 01/10 (bem atrasado, mês seguinte)
  perform public.efetivar_lancamento(l0.id, date '2026-10-01');

  -- contrato reancorado: novo dia é o do pagamento + 1 mês (01/11 → dia 1)
  assert (select dia_vencimento from public.contratos where id = v_ct) = 1, 'T1 contrato reancorado pro dia 1 (mês seguinte ao pagamento)';

  -- setembro (já gerada) vira pagamento + 1 mês = 01/11; outubro (já gerada) encadeia = 01/12
  assert (select data_vencimento from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-09-28') = date '2026-11-01',
    'T1 setembro (já gerada) = pagamento + 1 período, não o mesmo dia do pagamento';
  assert (select data_vencimento from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-10-28') = date '2026-12-01',
    'T1 outubro (já gerada) encadeia a partir de setembro, mais 1 período';

  -- agosto (já paga) não muda
  assert (select data_vencimento from public.lancamentos where id = l0.id) = date '2026-08-28', 'T1 agosto (já paga) intocada';
end $$;

-- T2: pago em dia não mexe em nada, mesmo em negócio pré-pago
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; v_venc_dep date; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug, ciclo_prepago) values (v.org, 'SERVIDOR PREPAGO DIA', 'servidor-prepago-dia', true) returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Prepago Em Dia') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Prepago Em Dia', 35) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 35, 'mensal', date '2026-08-10', 10) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct;
  perform public.gerar_faturamento_agora(date '2026-09-30');
  select data_vencimento into v_venc_dep from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-09-10';
  perform public.efetivar_lancamento(l0.id, date '2026-08-10'); -- em dia
  assert (select dia_vencimento from public.contratos where id = v_ct) = 10, 'T2 contrato não muda (pago em dia)';
  assert (select data_vencimento from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-09-10') = v_venc_dep,
    'T2 setembro não cascateou (pago em dia)';
end $$;

rollback;
\echo OK
