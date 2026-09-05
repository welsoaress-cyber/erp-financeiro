-- Testes da migration 0038 (cartão de crédito). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo, saldo_inicial) select org, 'Corrente Cart', 'corrente', 500 from ids;
insert into public.contas (organizacao_id, nome, tipo, saldo_inicial) select org, 'Cartao Teste', 'credito', 1000 from ids;
create temp table r as select (select org from ids) org,
  (select id from public.contas where nome='Corrente Cart') corrente,
  (select id from public.contas where nome='Cartao Teste') cartao,
  (select id from public.categorias where nome='Alimentação' limit 1) cat,
  least(extract(day from current_date)::int, 28) dia_fech;

-- T1: config exige conta de crédito
do $$ declare v r%rowtype; begin
  select * into v from r;
  begin
    insert into public.cartoes_config (organizacao_id, conta_id, dia_fechamento, dia_vencimento, limite_total)
    values (v.org, v.corrente, 10, 20, 100);
    raise exception 'T1 conta corrente não pode virar cartão';
  exception when check_violation then null; end;
  insert into public.cartoes_config (organizacao_id, conta_id, dia_fechamento, dia_vencimento, limite_total)
  values (v.org, v.cartao, v.dia_fech, v.dia_fech, 1000);
end $$;

-- T2: compra à vista consome limite; parcelada fica prevista (não consome)
do $$ declare v r%rowtype; begin
  select * into v from r;
  perform public.criar_lancamento('despesa', 'Mercado', 100, current_date, current_date, current_date, v.cartao, null, v.cat, null, null, null, null, false, null, null, null);
  perform public.criar_lancamento('despesa', 'Notebook', 90, current_date, current_date, null, v.cartao, null, v.cat, null, null, null, null, true, 'mensal', 3, null);
  assert (select saldo from public.vw_saldo_contas where id = v.cartao) = 900, 'T2 à vista consome, parcela prevista não';
end $$;

-- T3: fechamento consolida (efetiva a parcela do período) e não duplica
do $$ declare v r%rowtype; f public.faturas%rowtype; n int; begin
  select * into v from r;
  perform public.fechar_faturas_agora();
  select * into f from public.faturas where conta_id = v.cartao;
  assert f.valor_total = 190 and f.status in ('aberta', 'vencida'), 'T3 fatura 100 + parcela 90: ' || f.valor_total;
  select count(*) into n from public.fatura_itens where fatura_id = f.id; assert n = 2, 'T3 dois itens';
  assert (select saldo from public.vw_saldo_contas where id = v.cartao) = 810, 'T3 parcela efetivada consome limite';
  select count(*) into n from public.lancamentos where conta_id = v.cartao and status = 'previsto';
  assert n = 1, 'T3 parcela 2 gerada como prevista';
  perform public.fechar_faturas_agora();
  select count(*) into n from public.faturas where conta_id = v.cartao; assert n = 1, 'T3 idempotente';
end $$;

-- T4: pagamento parcial e total (transferência real restaura o valor pago)
do $$ declare v r%rowtype; f public.faturas%rowtype; begin
  select * into v from r;
  select * into f from public.faturas where conta_id = v.cartao;
  f := public.pagar_fatura(f.id, v.corrente, 50, current_date);
  assert f.valor_pago = 50 and f.status <> 'paga', 'T4 pagamento parcial';
  f := public.pagar_fatura(f.id, v.corrente, null, current_date);
  assert f.status = 'paga' and f.valor_pago = 190 and f.data_pagamento = current_date, 'T4 quitada';
  assert (select saldo from public.vw_saldo_contas where id = v.cartao) = 1000, 'T4 limite restaurado no valor pago';
  assert (select saldo from public.vw_saldo_contas where id = v.corrente) = 310, 'T4 corrente debitada';
  begin
    perform public.pagar_fatura(f.id, v.corrente, 10, current_date);
    raise exception 'T4 fatura paga não aceita novo pagamento';
  exception when check_violation then null; end;
end $$;

-- T5: fatura vencida é marcada pelo fechamento diário
do $$ declare v r%rowtype; n int; begin
  select * into v from r;
end $$;
reset role;
do $$ declare v r%rowtype; begin
  select * into v from r;
  perform set_config('erp.motor', 'on', true);
  insert into public.faturas (organizacao_id, conta_id, periodo_inicio, periodo_fim, data_vencimento, valor_total)
  values (v.org, v.cartao, current_date - 70, current_date - 40, current_date - 10, 10);
  perform set_config('erp.motor', 'off', true);
end $$;
set local role authenticated;
do $$ declare v r%rowtype; n int; begin
  select * into v from r;
  perform public.fechar_faturas_agora();
  select count(*) into n from public.faturas where conta_id = v.cartao and status = 'vencida';
  assert n = 1, 'T5 vencida marcada';
end $$;

rollback;
\echo OK
