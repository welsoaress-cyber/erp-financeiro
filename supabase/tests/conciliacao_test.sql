-- Testes da migration 0070 (conciliação bancária). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat uuid; v_l uuid; v_m uuid; n int; begin
  select id into v_org from public.organizacoes limit 1;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Conc Desp', 'despesa') returning id into v_cat;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'CONC T', 'conc-t', true) returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Banco Conc', 'corrente', v_neg) returning id into v_conta;
  select id into v_l from public.criar_lancamento('despesa', 'Conta de luz', 200, current_date, current_date, current_date, v_conta, null, v_cat, null, v_neg, null, null, false, null, null, null);
  select id into v_m from public.movimentos where lancamento_id = v_l;

  -- T1: marca como conciliado e desfaz
  n := public.conciliar_movimentos(array[v_m]);
  assert n = 1 and (select conciliado_em from public.movimentos where id = v_m) is not null, 'T1 conciliado';
  n := public.conciliar_movimentos(array[v_m], false);
  assert n = 1 and (select conciliado_em from public.movimentos where id = v_m) is null, 'T1 desfeito';

  -- T2: update direto continua barrado (sem grant / proteção)
  begin
    update public.movimentos set conciliado_em = now() where id = v_m;
    if (select conciliado_em from public.movimentos where id = v_m) is not null then
      raise exception 'T2 update direto deveria ser barrado';
    end if;
  exception when insufficient_privilege or check_violation then null; end;
end $$;

-- T3: fora da organização não concilia
set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
do $$ declare n int; begin
  begin
    n := public.conciliar_movimentos(array[gen_random_uuid()]);
    assert n = 0, 'T3 nada conciliado fora da organização';
  exception when insufficient_privilege then null; end;
end $$;

-- T4 (0142): corrigir_conta_lancamento move a baixa pra outra conta
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v_org uuid; v_neg uuid; v_c1 uuid; v_c2 uuid; v_cat uuid; v_l uuid; e public.lancamentos%rowtype; begin
  select id into v_org from public.organizacoes limit 1;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'CONC T2', 'conc-t2', true) returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Mercado Pago Conc', 'corrente', v_neg) returning id into v_c1;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Conc', 'dinheiro', v_neg) returning id into v_c2;
  select id into v_l from public.criar_lancamento('receita', 'Mensal/35', 35, current_date, current_date, current_date, v_c1, null, v_cat, null, v_neg, null, null, false, null, null, null);
  assert (select conta_id from public.movimentos where lancamento_id = v_l) = v_c1, 'T4 nasce na conta 1';

  e := public.corrigir_conta_lancamento(v_l, v_c2);
  assert e.conta_id = v_c2, 'T4 lançamento aponta pra conta 2';
  assert (select count(*) from public.movimentos where lancamento_id = v_l) = 1, 'T4 só um movimento (não duplica)';
  assert (select conta_id from public.movimentos where lancamento_id = v_l) = v_c2, 'T4 movimento migrou pra conta 2';
  assert (select valor from public.movimentos where lancamento_id = v_l) = 35, 'T4 valor intocado';

  -- previsto não pode (nada pra mover ainda)
  declare v_p uuid; begin
    select id into v_p from public.criar_lancamento('receita', 'Previsto', 10, current_date, current_date, null, v_c1, null, v_cat, null, v_neg, null, null, false, null, null, null);
    begin
      perform public.corrigir_conta_lancamento(v_p, v_c2);
      raise exception 'T4 previsto deveria falhar';
    exception when check_violation then null; end;
  end;

  -- transferência não pode (duas contas)
  declare v_t uuid; begin
    select id into v_t from public.criar_lancamento('transferencia', 'Transf', 20, current_date, current_date, current_date, v_c1, v_c2, null, null, v_neg, null, null, false, null, null, null);
    begin
      perform public.corrigir_conta_lancamento(v_t, v_c2);
      raise exception 'T4 transferência deveria falhar';
    exception when check_violation then null; end;
  end;
end $$;

rollback;
\echo OK
