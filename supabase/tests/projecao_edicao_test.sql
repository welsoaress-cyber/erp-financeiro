-- Testes da migration 0029 (projeção de recorrência + edição em lote). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Itaú', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Itaú') itau, (select id from public.categorias where nome='Moradia') moradia;

-- T1: projeção de despesa fixa (previsto, nunca paga) — 6 meses à frente
do $$ declare v r%rowtype; l1 public.lancamentos; n int; ultimo public.lancamentos; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Aluguel', 1500, date '2026-09-05', date '2026-09-05', null, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  select count(*) into n from public.lancamentos where lancamento_origem_id = l1.id; assert n = 0, 'T1 nada gerado antes de projetar';
  perform public.projetar_lancamento(l1.id, 6);
  select count(*) into n from public.lancamentos where recorrente and (id = l1.id or lancamento_origem_id is not null) and descricao = 'Aluguel'; assert n = 7, 'T1 7 parcelas (1 + 6 projetadas): ' || n;
  select * into ultimo from public.lancamentos where parcela_atual = 7 and descricao = 'Aluguel';
  assert ultimo.data_vencimento = date '2027-03-05' and ultimo.status = 'previsto', 'T1 última projetada em 03/2027, previsto: ' || ultimo.data_vencimento;
  -- projetar de novo não duplica, só continua da ponta
  perform public.projetar_lancamento(l1.id, 2);
  select count(*) into n from public.lancamentos where recorrente and descricao = 'Aluguel'; assert n = 9, 'T1 projeção soma a partir da ponta (9 no total)';
end $$;

-- T2: parcelamento — projeção respeita o número de parcelas
do $$ declare v r%rowtype; l1 public.lancamentos; n int; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Equipamento', 500, date '2026-09-10', date '2026-09-10', date '2026-09-10', v.itau, null, v.moradia, null, null, null, null, true, 'mensal', 3, null);
  perform public.projetar_lancamento(l1.id, 10);
  select count(*) into n from public.lancamentos where recorrente and descricao = 'Equipamento'; assert n = 3, 'T2 para nas 3 parcelas mesmo pedindo 10: ' || n;
end $$;

-- T3: horizonte inválido; lançamento não recorrente
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Bala', 2, date '2026-09-10', null, date '2026-09-10', v.itau, null, v.moradia, null, null, null, null, false, null, null, null);
  begin perform public.projetar_lancamento(l1.id, 3); raise exception 'T3 avulso não pode projetar'; exception when check_violation then null; end;
  l2 := public.criar_lancamento('despesa', 'Fixo', 100, date '2026-09-10', null, null, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  begin perform public.projetar_lancamento(l2.id, 0); raise exception 'T3 horizonte 0 deveria falhar'; exception when check_violation then null; end;
  begin perform public.projetar_lancamento(l2.id, 61); raise exception 'T3 horizonte 61 deveria falhar'; exception when check_violation then null; end;
end $$;

-- T4: edição em lote — escopo 'atual' só muda esta parcela
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; l3 public.lancamentos; begin
  select * into v from r;
  -- criado já pago (data_efetivacao preenchida) → fevereiro (l2) já nasce sozinho, previsto
  l1 := public.criar_lancamento('despesa', 'Aluguel', 1500, date '2026-01-05', date '2026-01-05', date '2026-01-05', v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  perform public.efetivar_lancamento(l2.id, date '2026-02-05'); -- paga fevereiro, gera março
  select * into l3 from public.lancamentos where lancamento_origem_id = l2.id;
  perform public.atualizar_lancamento_recorrente(l3.id, 'Aluguel reajustado', 1700, 'a partir de março', 'atual');
  select * into l3 from public.lancamentos where id = l3.id;
  assert l3.descricao = 'Aluguel reajustado' and l3.valor = 1700, 'T4 atual: só março mudou';
  select * into l1 from public.lancamentos where id = l1.id; select * into l2 from public.lancamentos where id = l2.id;
  assert l1.valor = 1500 and l2.valor = 1500, 'T4 atual: jan/fev continuam 1500';
end $$;

-- T5: edição em lote — escopo 'futuras' muda esta e as seguintes já geradas, mantém as passadas
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; n int; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Internet', 100, date '2026-01-10', date '2026-01-10', date '2026-01-10', v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id; -- fevereiro, já previsto
  perform public.projetar_lancamento(l2.id, 3); -- l2 (fev) + mar, abr, mai projetados
  select count(*) into n from public.lancamentos where recorrente and descricao = 'Internet'; assert n = 5, 'T5 5 no total (jan pago + fev..mai)';
  perform public.atualizar_lancamento_recorrente(l2.id, 'Internet fibra', 120, null, 'futuras');
  select * into l1 from public.lancamentos where id = l1.id; assert l1.valor = 100, 'T5 janeiro (passado) não muda';
  select count(*) into n from public.lancamentos where recorrente and descricao = 'Internet fibra' and valor = 120; assert n = 4, 'T5 fev, mar, abr, mai mudaram: ' || n;
end $$;

-- T6: edição em lote — escopo 'todas' alcança a cadeia inteira, inclusive já paga, e resincroniza o saldo
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; saldo_antes numeric; saldo_depois numeric; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Salário funcionário', 1000, date '2026-01-05', date '2026-01-05', date '2026-01-05', v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  select saldo into saldo_antes from public.vw_saldo_contas where id = v.itau;
  perform public.atualizar_lancamento_recorrente(l2.id, 'Salário funcionário', 1100, null, 'todas');
  select * into l1 from public.lancamentos where id = l1.id;
  assert l1.valor = 1100, 'T6 janeiro (já pago) também mudou: ' || l1.valor;
  assert (select valor from public.movimentos where lancamento_id = l1.id) = -1100, 'T6 movimento de janeiro resincronizado para -1100';
  select saldo into saldo_depois from public.vw_saldo_contas where id = v.itau;
  assert saldo_depois = saldo_antes - 100, 'T6 saldo caiu mais 100 com o reajuste de janeiro (já pago)';
end $$;

-- T7: escopo inválido; lançamento cancelado não pode ser alterado em lote
do $$ declare v r%rowtype; l1 public.lancamentos; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'X', 50, date '2026-09-01', null, null, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  begin perform public.atualizar_lancamento_recorrente(l1.id, 'X', 50, null, 'invalido'); raise exception 'T7 escopo inválido deveria falhar'; exception when check_violation then null; end;
  perform public.cancelar_lancamento(l1.id, 'teste');
  begin perform public.atualizar_lancamento_recorrente(l1.id, 'X', 50, null, 'atual'); raise exception 'T7 cancelado não pode ser alterado'; exception when check_violation then null; end;
end $$;
rollback;
\echo OK
