-- Testes da migration 0009 (faturamento recorrente). Saída final "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values ('22222222-2222-2222-2222-222222222222', 'bruno@teste.dev', '{"nome":"Bruno"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.negocios (organizacao_id, nome, slug) select org, 'SERVNET', 'servnet' from ids;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco', 'corrente' from ids;
insert into public.pessoas (organizacao_id, nome) select org, 'João' from ids;
insert into public.pessoas (organizacao_id, nome) select org, 'Maria' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) select org, (select id from public.negocios), 'Fibra', 100 from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) select org, (select id from public.negocios), 'Anual', 1200, 'anual' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) select org, (select id from public.negocios), 'Instalação', 300, 'unico' from ids;
create temp table r as select (select org from ids) org, (select id from public.negocios) neg, (select id from public.contas) banco,
  (select id from public.pessoas where nome='João') joao, (select id from public.pessoas where nome='Maria') maria,
  (select id from public.planos where nome='Fibra') fibra, (select id from public.planos where nome='Anual') anual, (select id from public.planos where nome='Instalação') inst,
  (select id from public.categorias where nome='Salário') cat_rec, (select id from public.categorias where nome='Alimentação') cat_desp;

-- Contrato mensal do João desde 2026-06, vencimento dia 31 (ajuste de fim de mês)
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
  select org, neg, joao, fibra, 100, 'mensal', '2026-06-15', 31 from r;

-- T1: sem configuração → pendência, nenhum lançamento
do $$ declare e public.faturamento_execucoes%rowtype; begin
  select * into e from public.gerar_faturamento_agora('2026-09-02');
  assert e.gerados = 0 and jsonb_array_length(e.pendencias) = 1 and e.pendencias->0->>'motivo' like 'Sem conta%', 'T1 pendência conta';
  update public.negocios set conta_padrao_id = (select banco from r);
  select * into e from public.gerar_faturamento_agora('2026-09-02');
  assert e.gerados = 0 and e.pendencias->0->>'motivo' like 'Negócio sem categoria%', 'T1 pendência categoria';
  begin
    update public.negocios set categoria_receita_id = (select cat_desp from r);
    raise exception 'T1 categoria de despesa deveria falhar';
  exception when check_violation then null; end;
  update public.negocios set categoria_receita_id = (select cat_rec from r);
end $$;

-- T2: geração mensal jun..set = 4 previstos, vencimentos ajustados, origem faturamento, herança
do $$ declare e public.faturamento_execucoes%rowtype; n int; begin
  select * into e from public.gerar_faturamento_agora('2026-09-02');
  assert e.gerados = 4 and jsonb_array_length(e.pendencias) = 0, 'T2 gerados ' || e.gerados;
  select count(*) into n from public.lancamentos where origem = 'faturamento' and status = 'previsto' and tipo = 'receita'; assert n = 4, 'T2 previstos';
  assert (select array_agg(data_vencimento order by data_vencimento) from public.lancamentos where origem = 'faturamento')
         = array['2026-06-30','2026-07-31','2026-08-31','2026-09-30']::date[], 'T2 vencimentos ajustados ao fim do mês';
  select count(*) into n from public.lancamentos l join public.contratos c on c.id = l.contrato_id
    where l.origem = 'faturamento' and l.negocio_id = c.negocio_id and l.pessoa_id = c.pessoa_id and l.valor = 100 and l.categoria_id = (select cat_rec from r) and l.conta_id = (select banco from r);
  assert n = 4, 'T2 herança e configuração';
  select count(*) into n from public.faturamentos; assert n = 4, 'T2 registros de faturamento';
  assert (select descricao from public.lancamentos where origem = 'faturamento' order by data_competencia limit 1) = 'Fibra · 06/2026 · contrato #001', 'T2 descrição';
end $$;

-- T3: idempotência; cancelar um previsto não faz regerar; mês seguinte gera só 1
do $$ declare e public.faturamento_execucoes%rowtype; v_l uuid; n int; begin
  select * into e from public.gerar_faturamento_agora('2026-09-02'); assert e.gerados = 0, 'T3 idempotente';
  select id into v_l from public.lancamentos where origem = 'faturamento' and data_competencia = '2026-07-31';
  perform public.cancelar_lancamento(v_l, 'teste');
  select * into e from public.gerar_faturamento_agora('2026-09-02'); assert e.gerados = 0, 'T3 cancelado não regera';
  select * into e from public.gerar_faturamento_agora('2026-10-01'); assert e.gerados = 1, 'T3 mês seguinte';
  select count(*) into n from public.vw_faturamentos where status_lancamento = 'cancelado'; assert n = 1, 'T3 view mostra status';
  begin
    perform public.gerar_faturamento_agora(current_date + 90);
    raise exception 'T3 limite de 2 meses deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T4: suspenso / automático desligado / faturar_desde → nada; anual → 1 por ano; único → 1
do $$ declare e public.faturamento_execucoes%rowtype; v_c uuid; n int; begin
  update public.contratos set status = 'suspenso' where codigo = 1;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, faturamento_automatico)
    select org, neg, maria, fibra, 50, 'mensal', '2026-01-01', 5, false from r;
  select * into e from public.gerar_faturamento_agora('2026-10-01'); assert e.gerados = 0, 'T4 suspenso e desligado';
  update public.contratos set faturamento_automatico = true, faturar_desde = '2026-09-01' where codigo = 2;
  select * into e from public.gerar_faturamento_agora('2026-10-01'); assert e.gerados = 2, 'T4 faturar_desde limita: set e out';
  -- (0027) ao criar já gera 2024-03 automaticamente
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    select org, neg, maria, anual, 1200, 'anual', '2024-03-10', 10 from r;
  select count(*) into n from public.faturamentos f join public.contratos c on c.id = f.contrato_id where c.codigo = 3; assert n = 1, 'T4 anual: 2024 já gerado ao criar';
  select * into e from public.gerar_faturamento_agora('2026-10-01'); assert e.gerados = 2, 'T4 anual 2025, 2026 (2024 já tinha sido gerado ao criar)';
  assert (select array_agg(data_vencimento order by 1) from public.lancamentos l join public.contratos c on c.id = l.contrato_id where c.codigo = 3)
         = array['2024-03-10','2025-03-10','2026-03-10']::date[], 'T4 anual datas';
  -- (0027) único: já gerado ao criar; a chamada seguinte não gera de novo
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    select org, neg, joao, inst, 300, 'unico', '2026-09-01', 20 from r;
  select count(*) into n from public.faturamentos f join public.contratos c on c.id = f.contrato_id where c.codigo = 4; assert n = 1, 'T4 único: já gerado ao criar';
  select * into e from public.gerar_faturamento_agora('2026-10-01'); assert e.gerados = 0, 'T4 único não gera de novo';
end $$;
-- geração para data distante só pelo motor interno (o RPC limita a 2 meses)
reset role;
do $$ declare e public.faturamento_execucoes%rowtype; n int; begin
  select * into e from public.gerar_faturamento((select org from r), '2027-01-01', 'manual'); assert e.gerados = 3, 'T4 janeiro: mensal nov, dez, jan';
  -- em 2027-01: contrato 2 (mensal, desde set/26) já tinha set..out; gera nov, dez, jan = 3; anual 2027 ainda não (março); único já gerado → total 3.
  select count(*) into n from public.faturamentos f join public.contratos c on c.id = f.contrato_id where c.codigo = 2; assert n = 5, 'T4 mensal set..jan';
  select count(*) into n from public.faturamentos f join public.contratos c on c.id = f.contrato_id where c.codigo = 4; assert n = 1, 'T4 único uma vez';
end $$;

-- T5: proteção — cliente não grava em faturamentos; RLS
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ begin
  begin
    insert into public.faturamentos (organizacao_id, contrato_id, competencia, lancamento_id) select organizacao_id, contrato_id, '2030-01-01', lancamento_id from public.faturamentos limit 1;
    raise exception 'T5 insert direto deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ declare n int; e record; begin
  select count(*) into n from public.faturamentos; assert n = 0, 'T5 rls faturamentos';
  select count(*) into n from public.faturamento_execucoes; assert n = 0, 'T5 rls execuções';
  select count(*) into n from public.gerar_faturamento_agora('2026-10-01'); assert n = 1, 'T5 Bruno gera só na própria organização';
end $$;

-- T6: execução agendada cobre todas as organizações (como postgres/cron)
reset role;
do $$ declare n int; begin
  perform public.gerar_faturamento_todas();
  select count(*) into n from public.faturamento_execucoes where origem = 'agendado'; assert n = 2, 'T6 uma execução por organização';
end $$;
rollback;
\echo OK
