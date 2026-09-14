-- Testes da migration 0082 (despesa vinculada ao contrato entra no payback; custo por cliente). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_rec uuid; v_desp uuid; v_p uuid; v_plano uuid; v_ct uuid; r record; begin
  select organizacao_id into v_org from public.categorias limit 1;
  select id into v_rec from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  select id into v_desp from public.categorias where organizacao_id = v_org and tipo = 'despesa' limit 1;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Caixa CCli', 'dinheiro') returning id into v_conta;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'CCLI T', 'ccli-t', true) returning id into v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Cliente Roteador') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano CCli', 100, 'mensal') returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, faturamento_automatico)
  values (v_org, v_neg, v_p, v_plano, 100, 'mensal', current_date - 90, 10, false) returning id into v_ct;

  -- roteador comprado para o cliente: despesa vinculada ao contrato (parcela prevista + parcela paga)
  perform public.criar_lancamento('despesa', 'Roteador parcela 1', 150, current_date - 80, current_date - 80, current_date - 80, v_conta, null, v_desp, null, v_neg, v_p, v_ct);
  perform public.criar_lancamento('despesa', 'Roteador parcela 2', 150, current_date - 50, current_date - 50, null, v_conta, null, v_desp, null, v_neg, v_p, v_ct);
  -- cancelada não conta
  perform public.cancelar_lancamento((public.criar_lancamento('despesa', 'Errada', 999, current_date - 50, current_date - 50, null, v_conta, null, v_desp, null, v_neg, v_p, v_ct)).id, 'teste');
  -- receitas: 100 (−80d), 100 (−50d), 100 (−20d) → acumulado ≥ 300 na 3ª
  perform public.criar_lancamento('receita', 'Mens 1', 100, current_date - 80, current_date - 80, current_date - 80, v_conta, null, v_rec, null, v_neg, v_p, v_ct);
  perform public.criar_lancamento('receita', 'Mens 2', 100, current_date - 50, current_date - 50, current_date - 50, v_conta, null, v_rec, null, v_neg, v_p, v_ct);
  perform public.criar_lancamento('receita', 'Mens 3', 100, current_date - 20, current_date - 20, current_date - 20, v_conta, null, v_rec, null, v_neg, v_p, v_ct);

  select * into r from public.vw_payback_contrato where contrato_id = v_ct;
  if r.despesas_contrato <> 300 then raise exception 'T1 despesas_contrato=%', r.despesas_contrato; end if;
  if r.custo_instalacao <> 300 then raise exception 'T1 custo=%', r.custo_instalacao; end if;
  if r.payback_estimado_meses <> 3 then raise exception 'T1 estimado=%', r.payback_estimado_meses; end if;
  if r.data_payback_real <> current_date - 20 then raise exception 'T1 payback real=%', r.data_payback_real; end if;

  select * into r from public.vw_rel_custo_cliente where contrato_id = v_ct;
  if r.pessoa <> 'Cliente Roteador' or r.receitas <> 300 or r.custo_total <> 300 or r.resultado <> 0 then raise exception 'T2 custo cliente: % % % %', r.pessoa, r.receitas, r.custo_total, r.resultado; end if;
end $$;

rollback;
\echo OK
