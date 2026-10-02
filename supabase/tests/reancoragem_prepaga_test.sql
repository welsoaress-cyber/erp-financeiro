-- Testes da migration 0120 (reancoragem diferente pra negócio pré-pago). Saída "OK".
-- Ajustado pela 0123: negócio pré-pago não acumula cobrança em aberto, então a
-- cascata pra "faturas futuras já geradas" raramente encontra mais de uma — o foco
-- aqui passa a ser: a PRÓXIMA cobrança gerada (depois do pagamento) usa o novo dia.
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Reanc Prepago', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco Reanc Prepago') conta;

-- T1: negócio pré-pago (ex.: Servidor Toptv) — vencia dia 28, cliente só paga dia 01 do mês
-- seguinte (bem atrasado). Enquanto não paga, o faturamento não gera nada em cima (0123).
-- Depois de pagar, a reancoragem (pagamento + 1 período, não o dia do mês) já vale pra
-- próxima cobrança que o faturamento gerar.
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; n int; v_dia smallint; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug, ciclo_prepago) values (v.org, 'SERVIDOR PREPAGO', 'servidor-prepago', true) returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Servidor Prepago') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Servidor Prepago', 35) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 35, 'mensal', date '2026-08-28', 28) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct; -- agosto, 28/08

  -- enquanto não paga, faturar de novo (mesmo bem depois) não gera nada em cima (0123)
  perform public.gerar_faturamento_agora(date '2026-10-31');
  assert (select count(*) from public.lancamentos where contrato_id = v_ct and status = 'previsto' and id <> l0.id) = 0,
    'T1 sem pagar, não acumula cobrança em cima';

  -- cliente só paga agosto em 01/10 (bem atrasado, mês seguinte)
  perform public.efetivar_lancamento(l0.id, date '2026-10-01');

  -- contrato reancorado: novo dia é o do pagamento + 1 mês (01/11 → dia 1)
  assert (select dia_vencimento from public.contratos where id = v_ct) = 1, 'T1 contrato reancorado pro dia 1 (mês seguinte ao pagamento)';

  -- agosto (já paga) não muda
  assert (select data_vencimento from public.lancamentos where id = l0.id) = date '2026-08-28', 'T1 agosto (já paga) intocada';

  -- só agora, depois de pago, o faturamento pode gerar a próxima — e já usa o novo dia
  perform public.gerar_faturamento_agora(date '2026-10-31');
  select count(*) into n from public.lancamentos where contrato_id = v_ct and status = 'previsto';
  assert n = 1, 'T1 gera só a próxima (uma de cada vez), não todo o atraso de uma vez: ' || n;
  select extract(day from data_vencimento)::smallint into v_dia from public.lancamentos where contrato_id = v_ct and status = 'previsto';
  assert v_dia = 1, 'T1 a próxima cobrança gerada já usa o novo dia (1), reancorado pelo pagamento';
end $$;

-- T2: pago em dia não mexe em nada, mesmo em negócio pré-pago
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug, ciclo_prepago) values (v.org, 'SERVIDOR PREPAGO DIA', 'servidor-prepago-dia', true) returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Prepago Em Dia') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Prepago Em Dia', 35) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 35, 'mensal', date '2026-08-10', 10) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct;
  perform public.efetivar_lancamento(l0.id, date '2026-08-10'); -- em dia
  assert (select dia_vencimento from public.contratos where id = v_ct) = 10, 'T2 contrato não muda (pago em dia)';
  perform public.gerar_faturamento_agora(date '2026-09-30');
  assert (select data_vencimento from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-09-10') = date '2026-09-10',
    'T2 setembro gerada no dia normal (pago em dia, sem reancoragem)';
end $$;

rollback;
\echo OK
