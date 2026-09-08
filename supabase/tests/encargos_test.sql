-- Testes da migration 0040 (encargos ao pagar com atraso). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Encargos', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco Encargos') conta, (select id from public.categorias where nome='Moradia') moradia;

-- T1: avulso pago atrasado com encargos → valor soma e observação registra
do $$ declare v r%rowtype; l public.lancamentos; begin
  select * into v from r;
  l := public.criar_lancamento('despesa', 'Obra Atraso', 1273.77, date '2026-08-25', date '2026-08-25', null, v.conta, null, v.moradia, null, null, null, null, false, null, null, null);
  l := public.efetivar_lancamento(l.id, date '2026-09-08', 25.40);
  assert l.valor = 1299.17, 'T1 valor com encargos: ' || l.valor;
  assert l.observacao like '%Encargos por atraso: R$ 25,40%', 'T1 observação: ' || coalesce(l.observacao, '<nula>');
  assert (select sum(m.valor) from public.movimentos m where m.lancamento_id = l.id) = -1299.17, 'T1 movimento com encargos';
end $$;

-- T2: recorrente fixa com encargos → só esta parcela muda; próximas mantêm o valor normal
do $$ declare v r%rowtype; l public.lancamentos; begin
  select * into v from r;
  l := public.criar_lancamento('despesa', 'Fixa Encargos', 100, date '2026-08-10', date '2026-08-10', null, v.conta, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  perform public.projetar_lancamento(l.id, 2);
  l := public.efetivar_lancamento(l.id, date '2026-08-20', 10);
  assert l.valor = 110, 'T2 parcela paga: ' || l.valor;
  assert (select count(*) from public.lancamentos where descricao = 'Fixa Encargos' and status = 'previsto' and valor = 100) = 2,
    'T2 futuras sem encargos';
end $$;

-- T3: encargos negativos são recusados; zero mantém tudo igual
do $$ declare v r%rowtype; l public.lancamentos; begin
  select * into v from r;
  l := public.criar_lancamento('despesa', 'Zero Encargos', 50, date '2026-09-01', date '2026-09-01', null, v.conta, null, v.moradia, null, null, null, null, false, null, null, null);
  begin
    perform public.efetivar_lancamento(l.id, date '2026-09-08', -1);
    raise exception 'T3 deveria recusar encargo negativo';
  exception when check_violation then null;
  end;
  l := public.efetivar_lancamento(l.id, date '2026-09-08', 0);
  assert l.valor = 50 and l.observacao is null, 'T3 zero não altera nada';
end $$;

rollback;
\echo OK
