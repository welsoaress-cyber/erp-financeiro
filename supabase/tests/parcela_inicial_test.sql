-- Testes da migration 0071 (parcelamento iniciando de parcela específica). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat uuid; l public.lancamentos%rowtype; n public.lancamentos%rowtype; begin
  select id into v_org from public.organizacoes limit 1;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Parc Desp', 'despesa') returning id into v_cat;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'PARC T', 'parc-t', true) returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Parc', 'dinheiro', v_neg) returning id into v_conta;

  -- T1: 24x iniciando na 2 → raiz nasce 2/24; efetivar gera a 3/24
  l := public.criar_lancamento('despesa', 'Estante 24x', 20, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, true, 'mensal', 24, null, 2);
  assert l.parcela_atual = 2 and l.numero_parcelas = 24 and l.tipo_recorrencia = 'parcelada', 'T1 raiz 2/24';
  perform public.efetivar_lancamento(l.id, current_date);
  select * into n from public.lancamentos where lancamento_origem_id = l.id;
  assert n.parcela_atual = 3 and n.numero_parcelas = 24, 'T1 próxima 3/24';

  -- T2: default continua 1; inicial inválida é barrada
  l := public.criar_lancamento('despesa', 'Normal 3x', 10, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, true, 'mensal', 3, null);
  assert l.parcela_atual = 1, 'T2 default parcela 1';
  begin
    perform public.criar_lancamento('despesa', 'Ruim', 10, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, true, 'mensal', 5, null, 6);
    raise exception 'T2 inicial > total deveria falhar';
  exception when check_violation then null; end;

  -- T3: iniciar na última parcela (24/24) não gera próxima ao efetivar
  l := public.criar_lancamento('despesa', 'Só falta a última', 20, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, true, 'mensal', 24, null, 24);
  perform public.efetivar_lancamento(l.id, current_date);
  assert not exists (select 1 from public.lancamentos where lancamento_origem_id = l.id), 'T3 última não gera próxima';
end $$;

rollback;
\echo OK
