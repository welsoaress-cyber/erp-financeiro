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

rollback;
\echo OK
