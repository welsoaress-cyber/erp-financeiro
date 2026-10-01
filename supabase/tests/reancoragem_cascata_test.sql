-- Testes da migration 0115 (reancoragem de contrato cascateia pras faturas futuras já geradas). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Reanc Casc', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco Reanc Casc') conta;

-- T1: servidor pré-pago — vencia dia 29, cliente paga dia 01. As faturas futuras
-- JÁ GERADAS (faturamento adiantado) acompanham o novo dia na mesma baixa.
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'SERVIDOR CASC', 'servidor-casc') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Servidor Casc') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Servidor Casc', 35) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 35, 'mensal', date '2026-08-29', 29) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct; -- 1ª cobrança, 29/08, gerada ao criar

  -- faturamento adiantado: gera também setembro e outubro (29/09, 29/10), ambos previstos
  perform public.gerar_faturamento_agora(date '2026-10-31');
  assert (select count(*) from public.lancamentos where contrato_id = v_ct and status = 'previsto' and id <> l0.id) = 2, 'T1 set/out geradas e previstas';

  -- cliente só paga a de agosto no dia 01/09 (atrasado)
  perform public.efetivar_lancamento(l0.id, date '2026-09-01');

  -- contrato reancorado pro dia 1
  assert (select dia_vencimento from public.contratos where id = v_ct) = 1, 'T1 contrato reancorado pro dia 1';

  -- setembro e outubro, que JÁ existiam como previsto, acompanham: 01/09 e 01/10
  assert (select data_vencimento from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-09-29') = date '2026-09-01',
    'T1 setembro (já gerada) cascateou pro dia 1';
  assert (select data_vencimento from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-10-29') = date '2026-10-01',
    'T1 outubro (já gerada) cascateou pro dia 1';

  -- a própria agosto (já paga) não muda — reancoragem nunca mexe no passado já efetivado
  assert (select data_vencimento from public.lancamentos where id = l0.id) = date '2026-08-29', 'T1 agosto (já paga) intocada';
end $$;

-- T2: pago em dia não cascateia nada (mesmo com faturas futuras já geradas)
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; v_venc_dep date; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'SERVIDOR CASC EM DIA', 'servidor-casc-dia') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Em Dia Casc') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Em Dia Casc', 35) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 35, 'mensal', date '2026-08-10', 10) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct;
  perform public.gerar_faturamento_agora(date '2026-09-30');
  select data_vencimento into v_venc_dep from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-09-10';
  perform public.efetivar_lancamento(l0.id, date '2026-08-10'); -- em dia
  assert (select dia_vencimento from public.contratos where id = v_ct) = 10, 'T2 contrato não muda';
  assert (select data_vencimento from public.lancamentos where contrato_id = v_ct and data_competencia = date '2026-09-10') = v_venc_dep,
    'T2 setembro não cascateou (pago em dia)';
end $$;

rollback;
\echo OK
