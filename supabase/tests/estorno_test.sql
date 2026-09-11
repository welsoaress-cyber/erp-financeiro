-- Testes da migration 0069 (estorno). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_c2 uuid; v_cat uuid; v_l uuid; v_pv uuid; v_tr uuid; e public.lancamentos%rowtype;
  v_mes date := date_trunc('month', current_date - interval '1 month')::date; s numeric; begin
  select id into v_org from public.organizacoes limit 1;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Est Desp', 'despesa') returning id into v_cat;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'EST T', 'est-t', true) returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Est', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Banco Est', 'corrente', v_neg) returning id into v_c2;

  -- T1: estorno de despesa efetivada em MÊS FECHADO devolve o caixa hoje, original intocado
  select id into v_l from public.criar_lancamento('despesa', 'Paga duplicada', 100, v_mes, v_mes, v_mes, v_conta, null, v_cat, null, v_neg, null, null, false, null, null, null);
  perform public.fechar_mes(v_mes);
  e := public.estornar_lancamento(v_l, 'Pagamento duplicado no banco');
  assert e.valor = -100 and e.origem::text = 'estorno' and e.estorno_de = v_l and e.data_efetivacao = current_date, 'T1 contra-lançamento';
  select coalesce(sum(valor), 0) into s from public.movimentos where conta_id = v_conta;
  assert s = 0, 'T1 caixa voltou a zero';
  assert (select status from public.lancamentos where id = v_l) = 'efetivado', 'T1 original intocado';

  -- T2: não estorna duas vezes; estorno não se estorna; previsto não estorna
  begin
    perform public.estornar_lancamento(v_l, 'De novo não');
    raise exception 'T2 estornar duas vezes deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.estornar_lancamento(e.id, 'Estorno do estorno');
    raise exception 'T2 estorno de estorno deveria falhar';
  exception when check_violation then null; end;
  select id into v_pv from public.criar_lancamento('despesa', 'Prevista', 10, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, false, null, null, null);
  begin
    perform public.estornar_lancamento(v_pv, 'Não dá');
    raise exception 'T2 previsto deveria falhar';
  exception when check_violation then null; end;

  -- T3: estorno de transferência inverte as duas pontas
  select id into v_tr from public.criar_lancamento('transferencia', 'Transf errada', 40, current_date, current_date, current_date, v_conta, v_c2, null, null, v_neg, null, null, false, null, null, null);
  perform public.estornar_lancamento(v_tr, 'Conta errada na transferência');
  select coalesce(sum(valor), 0) into s from public.movimentos where conta_id = v_c2;
  assert s = 0, 'T3 destino zerou';

  -- T4: cancelar o estorno reabre a possibilidade de estornar
  perform public.cancelar_lancamento(e.id, 'Estorno lançado errado');
  e := public.estornar_lancamento(v_l, 'Agora o estorno certo');
  assert e.valor = -100, 'T4 novo estorno após cancelar o anterior';
end $$;

rollback;
\echo OK
