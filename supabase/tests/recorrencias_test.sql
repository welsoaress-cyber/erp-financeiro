-- Testes da migration 0012 (recorrências em lançamentos). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Itaú', 'corrente' from ids;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Poupança', 'poupanca' from ids;
create temp table r as select
  (select org from ids) as org,
  (select id from public.contas where nome='Itaú') as itau,
  (select id from public.contas where nome='Poupança') as poup,
  (select id from public.categorias where nome='Moradia') as moradia,
  (select id from public.categorias where nome='Salário') as salario;

-- T0: próxima data mantém o dia-base e ajusta ao fim do mês
do $$ begin
  assert public.proxima_data_recorrencia(date '2026-09-10', 'mensal', 10) = date '2026-10-10', 'T0 mensal';
  assert public.proxima_data_recorrencia(date '2026-01-31', 'mensal', 31) = date '2026-02-28', 'T0 fim de mês';
  assert public.proxima_data_recorrencia(date '2026-02-28', 'mensal', 31) = date '2026-03-31', 'T0 volta ao dia 31';
  assert public.proxima_data_recorrencia(date '2026-09-10', 'quinzenal', 10) = date '2026-09-25', 'T0 quinzenal';
  assert public.proxima_data_recorrencia(date '2026-09-10', 'bimestral', 10) = date '2026-11-10', 'T0 bimestral';
  assert public.proxima_data_recorrencia(date '2026-09-10', 'trimestral', 10) = date '2026-12-10', 'T0 trimestral';
  assert public.proxima_data_recorrencia(date '2026-09-10', 'semestral', 10) = date '2027-03-10', 'T0 semestral';
  assert public.proxima_data_recorrencia(date '2026-09-10', 'anual', 10) = date '2027-09-10', 'T0 anual';
end $$;

-- T1: recorrente mensal com 3 parcelas — efetivar gera a próxima; a 3ª não gera a 4ª
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; l3 public.lancamentos; n int; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Aluguel', 1500, date '2026-09-10', date '2026-09-10', null, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', 3, null);
  assert l1.recorrente and l1.parcela_atual = 1 and l1.periodicidade = 'mensal' and l1.status = 'previsto', 'T1 parcela 1 prevista';
  select count(*) into n from public.lancamentos where lancamento_origem_id = l1.id; assert n = 0, 'T1 previsto não gera próxima';
  perform public.efetivar_lancamento(l1.id, date '2026-09-10');
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  assert found and l2.status = 'previsto' and l2.parcela_atual = 2 and l2.data_vencimento = date '2026-10-10' and l2.data_competencia = date '2026-10-10'
     and l2.valor = 1500 and l2.descricao = 'Aluguel' and l2.conta_id = v.itau and l2.categoria_id = v.moradia and l2.numero_parcelas = 3, 'T1 parcela 2 gerada por cópia';
  perform public.efetivar_lancamento(l2.id, date '2026-10-12');
  select * into l3 from public.lancamentos where lancamento_origem_id = l2.id;
  assert found and l3.parcela_atual = 3 and l3.data_vencimento = date '2026-11-10', 'T1 parcela 3 (vencimento pela parcela, não pela efetivação)';
  perform public.efetivar_lancamento(l3.id, date '2026-11-10');
  select count(*) into n from public.lancamentos where lancamento_origem_id = l3.id; assert n = 0, 'T1 parcela 3 de 3 não gera a 4ª';
  select count(*) into n from public.lancamentos where descricao = 'Aluguel'; assert n = 3, 'T1 total de 3 parcelas';
  -- saldo: só efetivados
  assert (select saldo from public.vw_saldo_contas where id = v.itau) = -4500, 'T1 saldo com 3 parcelas pagas';
end $$;

-- T2: criado já efetivado gera a próxima na hora; data de término interrompe na data certa; dia 31
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; l3 public.lancamentos; n int; begin
  select * into v from r;
  l1 := public.criar_lancamento('receita', 'Salário', 5000, date '2026-01-31', date '2026-01-31', date '2026-01-31', v.itau, null, v.salario, null, null, null, null, true, 'mensal', null, date '2026-03-31');
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  assert found and l2.data_vencimento = date '2026-02-28' and l2.parcela_atual = 2, 'T2 criado efetivado gera parcela 2 (fim de mês)';
  perform public.efetivar_lancamento(l2.id, date '2026-02-28');
  select * into l3 from public.lancamentos where lancamento_origem_id = l2.id;
  assert found and l3.data_vencimento = date '2026-03-31', 'T2 parcela 3 volta ao dia 31 (dia-base da 1ª)';
  perform public.efetivar_lancamento(l3.id, date '2026-03-31');
  select count(*) into n from public.lancamentos where lancamento_origem_id = l3.id; assert n = 0, 'T2 término 31/03 atingido: não gera 30/04';
end $$;

-- T3: cancelar previsto interrompe; cancelar efetivado não interrompe (só estorna)
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; n int; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Academia', 99.9, date '2026-09-05', date '2026-09-05', date '2026-09-05', v.itau, null, v.moradia, null, null, null, null, true, 'mensal', 12, null);
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id; assert found, 'T3 parcela 2 existe';
  perform public.cancelar_lancamento(l1.id, 'estorno');
  select * into l2 from public.lancamentos where id = l2.id; assert l2.status = 'previsto', 'T3 cancelar efetivado mantém a parcela 2 prevista';
  perform public.cancelar_lancamento(l2.id, 'parei');
  select count(*) into n from public.lancamentos where lancamento_origem_id = l2.id; assert n = 0, 'T3 cancelar previsto: nada gerado';
  begin
    perform public.efetivar_lancamento(l2.id, date '2026-10-05');
    raise exception 'T3 efetivar cancelado deveria falhar';
  exception when check_violation then null; end;
  select count(*) into n from public.lancamentos where descricao = 'Academia'; assert n = 2, 'T3 cadeia parou em 2';
end $$;

-- T4: edição bloqueada após parcelas geradas (exceto descrição/observação); recorrência imutável na parcela 2
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; x public.lancamentos; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Internet', 120, date '2026-09-15', date '2026-09-15', date '2026-09-15', v.itau, null, v.moradia, null, null, null, null, true, 'mensal', 6, null);
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  -- descrição e observação podem
  x := public.atualizar_lancamento(l1.id, 'Internet fibra', 120, date '2026-09-15', date '2026-09-15', date '2026-09-15', v.itau, null, v.moradia, 'obs', null, null, null, true, 'mensal', 6, null);
  assert x.descricao = 'Internet fibra' and x.observacao = 'obs', 'T4 descrição/observação editáveis';
  -- valor pode (0025); conta não
  x := public.atualizar_lancamento(l1.id, 'Internet fibra', 130, date '2026-09-15', date '2026-09-15', date '2026-09-15', v.itau, null, v.moradia, 'obs', null, null, null, true, 'mensal', 6, null);
  assert x.valor = 130, 'T4 valor editável';
  begin
    perform public.atualizar_lancamento(l1.id, 'Internet fibra', 130, date '2026-09-15', date '2026-09-15', date '2026-09-15', v.poup, null, v.moradia, 'obs', null, null, null, true, 'mensal', 6, null);
    raise exception 'T4 conta deveria ser bloqueada';
  exception when check_violation then assert sqlerrm like 'Lançamento com parcelas geradas%', 'T4 msg conta: ' || sqlerrm; end;
  begin
    perform public.atualizar_lancamento(l1.id, 'Internet fibra', 120, date '2026-09-15', date '2026-09-15', date '2026-09-15', v.itau, null, v.moradia, 'obs', null, null, null, true, 'mensal', 10, null);
    raise exception 'T4 número de parcelas deveria ser bloqueado';
  exception when check_violation then assert sqlerrm like 'A recorrência não pode ser alterada%', 'T4 msg parcelas: ' || sqlerrm; end;
  begin
    perform public.atualizar_lancamento(l2.id, 'Internet fibra', 120, l2.data_competencia, l2.data_vencimento, null, v.itau, null, v.moradia, null, null, null, null, true, 'anual', 6, null);
    raise exception 'T4 periodicidade da parcela 2 deveria ser bloqueada';
  exception when check_violation then null; end;
  -- parcela 2 (sem filha) pode ter o valor ajustado; a 3ª herda o novo valor
  x := public.atualizar_lancamento(l2.id, 'Internet fibra', 135, l2.data_competencia, l2.data_vencimento, null, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', 6, null);
  assert x.valor = 135, 'T4 valor da parcela 2 ajustado';
  perform public.efetivar_lancamento(l2.id, date '2026-10-15');
  assert (select valor from public.lancamentos where lancamento_origem_id = l2.id) = 135, 'T4 parcela 3 herda valor ajustado';
end $$;

-- T5: validações — sem periodicidade; sem parcelas nem término; término antes do vencimento; faturamento não pode ser recorrente; excluir previsto interrompe; transferência recorrente ok
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; n int; begin
  select * into v from r;
  begin
    perform public.criar_lancamento('despesa', 'X', 10, date '2026-09-01', null, null, v.itau, null, v.moradia, null, null, null, null, true, null, 3, null);
    raise exception 'T5 sem periodicidade deveria falhar';
  exception when check_violation or not_null_violation then null; end;
  -- (0025) sem parcelas nem término = despesa fixa, válido
  assert (public.criar_lancamento('despesa', 'X', 10, date '2026-09-01', null, null, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, null)).tipo_recorrencia = 'fixa', 'T5 fixa sem término';
  begin
    perform public.criar_lancamento('despesa', 'X', 10, date '2026-09-01', null, null, v.itau, null, v.moradia, null, null, null, null, true, 'mensal', null, date '2026-08-01');
    raise exception 'T5 término antes do vencimento deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.criar_lancamento('despesa', 'X', 10, date '2026-09-01', null, null, v.itau, null, v.moradia, null, null, null, null, true, 'semanal', 3, null);
    raise exception 'T5 periodicidade inválida deveria falhar';
  exception when invalid_text_representation then null; end;
  -- avulso: colunas nulas mesmo se enviadas
  l1 := public.criar_lancamento('despesa', 'Avulso', 10, date '2026-09-01', null, null, v.itau, null, v.moradia, null, null, null, null, false, 'mensal', 3, null);
  assert not l1.recorrente and l1.periodicidade is null and l1.parcela_atual is null, 'T5 avulso ignora dados de recorrência';
  -- transferência recorrente
  l1 := public.criar_lancamento('transferencia', 'Reserva', 300, date '2026-09-20', null, date '2026-09-20', v.itau, v.poup, null, null, null, null, null, true, 'mensal', 2, null);
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  assert found and l2.tipo = 'transferencia' and l2.conta_destino_id = v.poup, 'T5 transferência recorrente copia destino';
  -- excluir previsto da cadeia: para
  perform public.excluir_lancamento(l2.id);
  select count(*) into n from public.lancamentos where lancamento_origem_id = l1.id; assert n = 0, 'T5 parcela prevista excluída';
  -- função interna não é chamável pelo cliente
  begin
    perform public.gerar_proxima_parcela(l1.id);
    raise exception 'T5 gerar_proxima_parcela deveria ser interna';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
\echo OK
