-- Testes da migration 0025 (despesa fixa × parcelamento). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Itaú', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Itaú') itau, (select id from public.categorias where nome='Moradia') moradia;

-- T1: despesa fixa — sem parcelas nem término; efetivar gera o próximo mês; tipo derivado
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; l3 public.lancamentos; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Aluguel', 1500, date '2026-09-05', date '2026-09-05', null, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  assert l1.recorrente and l1.tipo_recorrencia = 'fixa' and l1.numero_parcelas is null and l1.parcela_atual = 1, 'T1 fixa criada: ' || l1.tipo_recorrencia::text;
  perform public.efetivar_lancamento(l1.id, date '2026-09-05');
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  assert l2.id is not null and l2.tipo_recorrencia = 'fixa' and l2.parcela_atual = 2 and l2.data_vencimento = date '2026-10-05' and l2.status = 'previsto' and l2.valor = 1500, 'T1 próximo mês gerado';
  perform public.efetivar_lancamento(l2.id, date '2026-10-05');
  select * into l3 from public.lancamentos where lancamento_origem_id = l2.id;
  assert l3.parcela_atual = 3 and l3.data_vencimento = date '2026-11-05', 'T1 fixa continua indefinidamente';
  -- valor editável mesmo com parcelas geradas (regra: só descrição e valor)
  l1 := public.atualizar_lancamento(l1.id, 'Aluguel reajustado', 1600, l1.data_competencia, l1.data_vencimento, l1.data_efetivacao, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  assert l1.valor = 1600 and l1.descricao = 'Aluguel reajustado', 'T1 valor/descrição editáveis';
  -- cancelar a prevista interrompe
  perform public.cancelar_lancamento(l3.id, 'Mudei de casa');
  assert (select count(*) from public.lancamentos where lancamento_origem_id = l3.id) = 0, 'T1 cancelada não gera';
end $$;

-- T2: parcelamento — N parcelas, para na última; tipo parcelada
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; n int; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Equipamento 2x', 500, date '2026-09-10', date '2026-09-10', date '2026-09-10', v.itau, null, v.moradia, null, null, null, null, true, 'mensal', 2, null);
  assert l1.tipo_recorrencia = 'parcelada' and l1.numero_parcelas = 2, 'T2 parcelada';
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  assert l2.parcela_atual = 2 and l2.tipo_recorrencia = 'parcelada', 'T2 parcela 2 gerada';
  perform public.efetivar_lancamento(l2.id, date '2026-10-10');
  select count(*) into n from public.lancamentos where lancamento_origem_id = l2.id; assert n = 0, 'T2 parou na última parcela';
  -- não dá para virar fixa depois de gerar parcelas
  begin
    perform public.atualizar_lancamento(l1.id, 'Equipamento 2x', 500, l1.data_competencia, l1.data_vencimento, l1.data_efetivacao, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
    raise exception 'T2 mudar parcelada→fixa deveria falhar';
  exception when check_violation then null; end;
  -- constraint: parcelada exige parcelas ≥ 2 (check da 0012 mantido)
  begin
    perform public.criar_lancamento('despesa', 'X', 10, date '2026-09-10', null, null, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', 1, null);
    raise exception 'T2 1 parcela deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: avulso não tem tipo
do $$ declare v r%rowtype; l public.lancamentos; begin
  select * into v from r;
  l := public.criar_lancamento('despesa', 'Bala', 2, date '2026-09-10', null, date '2026-09-10', v.itau, null, v.moradia, null, null, null, null, false, null, null, null);
  assert not l.recorrente and l.tipo_recorrencia is null, 'T3 avulso';
  assert (select count(*) from public.lancamentos where lancamento_origem_id = l.id) = 0, 'T3 avulso não gera';
end $$;
rollback;
\echo OK
