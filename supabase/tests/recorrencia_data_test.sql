-- Testes da migration 0032 (edição de data em recorrência com parcelas geradas). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Nubank Data', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Nubank Data') conta, (select id from public.categorias where nome='Moradia') moradia;

-- T1: escopo 'atual' muda a data só desta parcela prevista
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Técnico', 1000, date '2026-09-01', date '2026-09-01', null, v.conta, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  perform public.projetar_lancamento(l1.id, 3);
  perform public.atualizar_lancamento_recorrente(l1.id, 'Técnico', 1000, null, 'atual', date '2026-09-15');
  select * into l1 from public.lancamentos where id = l1.id;
  assert l1.data_vencimento = date '2026-09-15' and l1.data_competencia = date '2026-09-15', 'T1 data desta mudou';
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  assert l2.data_vencimento = date '2026-10-01', 'T1 seguinte não mudou: ' || l2.data_vencimento;
end $$;

-- T2: escopo 'futuras' desloca esta e as seguintes previstas para o novo dia
do $$ declare v r%rowtype; l1 public.lancamentos; n int; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Aluguel D', 1500, date '2026-09-05', date '2026-09-05', null, v.conta, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  perform public.projetar_lancamento(l1.id, 3); -- 4 parcelas: 09..12, dia 05
  perform public.atualizar_lancamento_recorrente(l1.id, 'Aluguel D', 1500, null, 'futuras', date '2026-09-20');
  select count(*) into n from public.lancamentos where descricao = 'Aluguel D'
    and data_vencimento in (date '2026-09-20', date '2026-10-20', date '2026-11-20', date '2026-12-20');
  assert n = 4, 'T2 cadeia inteira no dia 20: ' || n;
end $$;

-- T3: 'todas' com data é recusado; efetivada não muda de data
do $$ declare v r%rowtype; l1 public.lancamentos; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Luz D', 200, date '2026-09-08', date '2026-09-08', date '2026-09-08', v.conta, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  begin
    perform public.atualizar_lancamento_recorrente(l1.id, 'Luz D', 200, null, 'todas', date '2026-09-25');
    raise exception 'T3 todas + data deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.atualizar_lancamento_recorrente(l1.id, 'Luz D', 200, null, 'atual', date '2026-09-25');
    raise exception 'T3 efetivada não pode mudar de data';
  exception when check_violation then null; end;
end $$;

-- T4: 'futuras' com parcela paga no meio: a paga não move, as previstas seguintes movem
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; l3 public.lancamentos; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Net D', 100, date '2026-01-10', date '2026-01-10', null, v.conta, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  perform public.projetar_lancamento(l1.id, 2); -- jan, fev, mar
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  perform public.efetivar_lancamento(l2.id, date '2026-02-10'); -- paga fevereiro (gera abril na ponta)
  perform public.atualizar_lancamento_recorrente(l1.id, 'Net D', 100, null, 'futuras', date '2026-01-25');
  select * into l1 from public.lancamentos where id = l1.id;
  select * into l2 from public.lancamentos where id = l2.id;
  select * into l3 from public.lancamentos where lancamento_origem_id = l2.id;
  assert l1.data_vencimento = date '2026-01-25', 'T4 janeiro moveu para 25';
  assert l2.data_vencimento = date '2026-02-10', 'T4 fevereiro pago não moveu';
  assert l3.data_vencimento = date '2026-03-25', 'T4 março previsto moveu para 25: ' || l3.data_vencimento;
end $$;

rollback;
\echo OK
