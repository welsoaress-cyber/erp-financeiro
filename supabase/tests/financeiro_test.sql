-- Testes da migration 0026 (baixa parcial). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Itaú', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Itaú') itau, (select id from public.categorias where nome='Moradia') moradia, (select id from public.categorias where nome='Salário') salario;

-- T1: baixa parcial de uma receita prevista → original efetivada com o valor pago + restante previsto
do $$ declare v r%rowtype; l public.lancamentos; x public.lancamentos; rest public.lancamentos; begin
  select * into v from r;
  l := public.criar_lancamento('receita', 'Consultoria', 1000, date '2026-09-10', date '2026-09-10', null, v.itau, null, v.salario, null, null, null, null, false, null, null, null);
  begin
    perform public.baixar_parcial(l.id, 1000, date '2026-09-10');
    raise exception 'T1 valor igual deveria falhar';
  exception when check_violation then null; end;
  x := public.baixar_parcial(l.id, 400, date '2026-09-08');
  assert x.status = 'efetivado' and x.valor = 400 and x.data_efetivacao = date '2026-09-08', 'T1 original efetivada com 400';
  select * into rest from public.lancamentos where descricao = 'Consultoria' and status = 'previsto';
  assert rest.valor = 600 and rest.data_vencimento = date '2026-09-10' and rest.observacao like 'Saldo restante após baixa parcial de R$ 400,00 em 08/09/2026.%' and not rest.recorrente, 'T1 restante 600: ' || coalesce(rest.observacao, '');
  assert (select coalesce(sum(valor), 0) from public.movimentos where lancamento_id = x.id) = 400, 'T1 movimento de 400';
  begin
    perform public.baixar_parcial(x.id, 100, current_date);
    raise exception 'T1 efetivado não aceita baixa parcial';
  exception when check_violation then null; end;
  -- segunda baixa parcial no restante
  x := public.baixar_parcial(rest.id, 100, date '2026-09-12');
  assert x.valor = 100 and (select valor from public.lancamentos where descricao = 'Consultoria' and status = 'previsto') = 500, 'T1 segunda baixa';
end $$;

-- T2: baixa parcial em despesa fixa gera o próximo mês com o valor cheio
do $$ declare v r%rowtype; l public.lancamentos; x public.lancamentos; prox public.lancamentos; begin
  select * into v from r;
  l := public.criar_lancamento('despesa', 'Aluguel', 1500, date '2026-09-05', date '2026-09-05', null, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  x := public.baixar_parcial(l.id, 1000, date '2026-09-05');
  assert x.valor = 1000 and x.status = 'efetivado', 'T2 pago 1000';
  select * into prox from public.lancamentos where lancamento_origem_id = l.id;
  assert prox.valor = 1500 and prox.data_vencimento = date '2026-10-05' and prox.tipo_recorrencia = 'fixa', 'T2 próximo mês com valor cheio';
  assert (select valor from public.lancamentos where descricao = 'Aluguel' and status = 'previsto' and not recorrente) = 500, 'T2 restante 500 avulso';
end $$;

-- T3: transferência e valores inválidos
do $$ declare v r%rowtype; l public.lancamentos; begin
  select * into v from r;
  l := public.criar_lancamento('despesa', 'Luz', 200, date '2026-09-10', null, null, v.itau, null, v.moradia, null, null, null, null, false, null, null, null);
  begin perform public.baixar_parcial(l.id, 0, current_date); raise exception 'T3 zero'; exception when check_violation then null; end;
  begin perform public.baixar_parcial(l.id, -5, current_date); raise exception 'T3 negativo'; exception when check_violation then null; end;
end $$;
rollback;
\echo OK
