-- Testes da migration 0144 (tabela + relatório de divergências Asaas). Saída "OK".
\set ON_ERROR_STOP on
begin;

-- fixture: insere direto como postgres (só a reconciliação agendada, fora do alcance do teste local, grava de verdade)
do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat uuid; v_pes uuid; v_l uuid; begin
  select id into v_org from public.organizacoes limit 1;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'ASAAS DIV T', 'asaas-div-t', true) returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Conta Div', 'corrente', v_neg) returning id into v_conta;
  insert into public.pessoas (organizacao_id, nome, documento) values (v_org, 'Cliente Divergente', '52998224725') returning id into v_pes;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  select id into v_l from public.criar_lancamento('receita', 'Mensal', 80, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, v_pes, null, false, null, null, null);
  reset role;
  insert into public.asaas_divergencias (organizacao_id, lancamento_id, pessoa_id, valor_esperado, vencimento_esperado, pagamento)
  values (v_org, v_l, v_pes, 80, current_date, jsonb_build_object('id', 'pay_teste', 'value', 95.50, 'dueDate', (current_date + 3)::text, 'status', 'RECEIVED'));
  create temp table idsdiv as select v_org org, v_l lanc, v_pes pes;
end $$;
grant select on idsdiv to authenticated;

-- T1: a view traz a divergência com os campos certos
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v record; i record; begin
  select * into i from idsdiv;
  select * into v from public.vw_rel_asaas_divergencias where lancamento_id = i.lanc;
  assert found, 'T1 divergência aparece na view';
  assert v.cliente = 'Cliente Divergente', 'T1 nome do cliente: ' || v.cliente;
  assert v.valor_esperado = 80 and v.valor_pago = 95.50, 'T1 valores esperado vs pago: ' || v.valor_esperado || ' / ' || v.valor_pago;
  assert v.vencimento_pago = (current_date + 3), 'T1 vencimento pago: ' || v.vencimento_pago;
  assert v.status_pagamento = 'RECEIVED', 'T1 status: ' || v.status_pagamento;
end $$;

-- T2: fora da organização não vê nada (RLS)
set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
do $$ declare n int; i record; begin
  select * into i from idsdiv;
  select count(*) into n from public.vw_rel_asaas_divergencias where lancamento_id = i.lanc;
  assert n = 0, 'T2 RLS: fora da organização não vê a divergência';
end $$;

-- T3: authenticated não pode escrever direto (só a função agendada)
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare i record; begin
  select * into i from idsdiv;
  begin
    update public.asaas_divergencias set valor_esperado = 999 where lancamento_id = i.lanc;
    raise exception 'T3 update direto deveria ser barrado';
  exception when insufficient_privilege then null; end;
end $$;

rollback;
\echo OK
