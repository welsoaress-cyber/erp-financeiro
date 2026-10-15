-- Testes da migration 0147 (histórico + relatório de baixas automáticas Asaas). Saída "OK".
\set ON_ERROR_STOP on
begin;

-- fixture: insere direto como postgres (só a reconciliação agendada, fora do alcance do teste local, grava de verdade)
do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat uuid; v_pes uuid; v_l uuid; begin
  select id into v_org from public.organizacoes limit 1;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'ASAAS BAIXA T', 'asaas-baixa-t', true) returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Conta Baixa', 'corrente', v_neg) returning id into v_conta;
  insert into public.pessoas (organizacao_id, nome, documento) values (v_org, 'Cliente Baixado', '52998224725') returning id into v_pes;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  select id into v_l from public.criar_lancamento('receita', 'Mensal', 70, current_date, current_date, current_date, v_conta, null, v_cat, null, v_neg, v_pes, null, false, null, null, null);
  reset role;
  insert into public.asaas_baixas_automaticas (organizacao_id, lancamento_id, pessoa_id, negocio_id, valor, data_pagamento, forma_pagamento, pagamento)
  values (v_org, v_l, v_pes, v_neg, 70, current_date, 'pix', jsonb_build_object('id', 'pay_x', 'billingType', 'PIX', 'status', 'RECEIVED'));
  create temp table idsbx as select v_org org, v_l lanc, v_pes pes, v_neg neg;
end $$;
grant select on idsbx to authenticated;

-- T1: a view traz a baixa com os campos certos
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v record; i record; begin
  select * into i from idsbx;
  select * into v from public.vw_rel_asaas_baixas_automaticas where lancamento_id = i.lanc;
  assert found, 'T1 baixa aparece na view';
  assert v.cliente = 'Cliente Baixado', 'T1 cliente: ' || v.cliente;
  assert v.valor = 70 and v.forma_pagamento = 'pix', 'T1 valor/forma: ' || v.valor || ' / ' || v.forma_pagamento;
  assert v.forma_cobranca_asaas = 'PIX' and v.pagamento_asaas_id = 'pay_x', 'T1 dados do pagamento Asaas: ' || v.forma_cobranca_asaas;
end $$;

-- T2: fora da organização não vê nada (RLS)
set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
do $$ declare n int; i record; begin
  select * into i from idsbx;
  select count(*) into n from public.vw_rel_asaas_baixas_automaticas where lancamento_id = i.lanc;
  assert n = 0, 'T2 RLS: fora da organização não vê a baixa';
end $$;

-- T3: authenticated não pode escrever direto (só a reconciliação agendada)
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare i record; begin
  select * into i from idsbx;
  begin
    update public.asaas_baixas_automaticas set valor = 999 where lancamento_id = i.lanc;
    raise exception 'T3 update direto deveria ser barrado';
  exception when insufficient_privilege then null; end;
end $$;

rollback;
\echo OK
