-- Testes da migration 0031 (projeção de contratos). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.negocios (organizacao_id, nome, slug) select org, 'PROJ TESTE', 'proj-teste' from ids;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Proj', 'corrente' from ids;
insert into public.pessoas (organizacao_id, nome) select org, 'Cliente Proj' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) select org, (select id from public.negocios where slug='proj-teste'), 'Fibra Proj', 100 from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) select org, (select id from public.negocios where slug='proj-teste'), 'Anual Proj', 1200, 'anual' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) select org, (select id from public.negocios where slug='proj-teste'), 'Instalação Proj', 300, 'unico' from ids;
update public.negocios set conta_padrao_id = (select id from public.contas where nome='Banco Proj'),
  categoria_receita_id = (select id from public.categorias where nome='Salário' limit 1)
  where slug='proj-teste';
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='proj-teste') neg,
  (select id from public.pessoas where nome='Cliente Proj') cli,
  (select id from public.planos where nome='Fibra Proj') fibra,
  (select id from public.planos where nome='Anual Proj') anual,
  (select id from public.planos where nome='Instalação Proj') inst,
  date_trunc('month', current_date)::date mes_atual,
  (date_trunc('month', current_date) + interval '1 month')::date mes_seguinte;

-- Contrato mensal desde 2 meses atrás, vencimento dia 31 (ajuste de fim de mês)
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
  select org, neg, cli, fibra, 100, 'mensal', (mes_atual - interval '2 months')::date, 31 from r;
select public.gerar_faturamento_agora(current_date);

-- T1: próximo mês tem exatamente 1 projeção do contrato, valor atual, tipo receita
do $$ declare p record; n int; begin
  select count(*) into n from public.projecao_contratos((select org from r), (select mes_seguinte from r), ((select mes_seguinte from r) + interval '1 month' - interval '1 day')::date)
    where contrato_id = (select id from public.contratos where plano_id = (select fibra from r));
  assert n = 1, 'T1 uma projeção no mês seguinte, veio ' || n;
  select * into p from public.projecao_contratos((select org from r), (select mes_seguinte from r), ((select mes_seguinte from r) + interval '1 month' - interval '1 day')::date)
    where contrato_id = (select id from public.contratos where plano_id = (select fibra from r));
  assert p.valor = 100 and p.tipo = 'receita', 'T1 valor/tipo';
  assert p.data_vencimento = ((select mes_seguinte from r) + interval '1 month' - interval '1 day')::date, 'T1 vencimento dia 31 ajustado ao fim do mês';
  assert p.descricao like 'Fibra Proj · %', 'T1 descrição';
end $$;

-- T2: mês corrente (já faturado pelo motor real) não aparece na projeção
do $$ declare n int; begin
  select count(*) into n from public.projecao_contratos((select org from r), (select mes_atual from r), ((select mes_seguinte from r) - interval '1 day')::date);
  assert n = 0, 'T2 mês corrente fora da projeção, veio ' || n;
end $$;

-- T3: horizonte de 60 meses = 60 projeções mensais; acima do teto, erro
do $$ declare n int; begin
  select count(*) into n from public.projecao_contratos((select org from r), (select mes_seguinte from r), ((select mes_atual from r) + interval '60 months')::date)
    where contrato_id = (select id from public.contratos where plano_id = (select fibra from r));
  assert n = 60, 'T3 60 meses projetados, veio ' || n;
  begin
    perform public.projecao_contratos((select org from r), (select mes_seguinte from r), ((select mes_atual from r) + interval '62 months')::date);
    raise exception 'T3 deveria recusar horizonte acima de 60 meses';
  exception when check_violation then null; end;
end $$;

-- T4: reajuste do contrato reflete na projeção imediatamente (nada congelado)
do $$ declare p record; begin
  update public.contratos set valor = 150 where plano_id = (select fibra from r);
  select * into p from public.projecao_contratos((select org from r), (select mes_seguinte from r), (select mes_seguinte from r));
  assert p.valor = 150, 'T4 projeção com valor reajustado';
end $$;

-- T5: suspender some da projeção; reativar volta
do $$ declare n int; begin
  update public.contratos set status = 'suspenso' where plano_id = (select fibra from r);
  select count(*) into n from public.projecao_contratos((select org from r), (select mes_seguinte from r), (select mes_seguinte from r));
  assert n = 0, 'T5 suspenso sem projeção';
  update public.contratos set status = 'ativo' where plano_id = (select fibra from r);
  select count(*) into n from public.projecao_contratos((select org from r), (select mes_seguinte from r), (select mes_seguinte from r));
  assert n = 1, 'T5 reativado volta à projeção';
end $$;

-- T6: contrato anual projeta só os aniversários (5 em 60 meses); único não projeta
do $$ declare n int; begin
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    select org, neg, cli, anual, 1200, 'anual', current_date, 10 from r;
  select count(*) into n from public.projecao_contratos((select org from r), (select mes_seguinte from r), ((select mes_atual from r) + interval '60 months')::date)
    where contrato_id = (select id from public.contratos where plano_id = (select anual from r));
  assert n = 5, 'T6 anual: 5 aniversários em 60 meses, veio ' || n;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    select org, neg, cli, inst, 300, 'unico', current_date, 10 from r;
  select count(*) into n from public.projecao_contratos((select org from r), (select mes_seguinte from r), ((select mes_atual from r) + interval '60 months')::date)
    where contrato_id = (select id from public.contratos where plano_id = (select inst from r));
  assert n = 0, 'T6 único não projeta, veio ' || n;
end $$;

-- T7: quem não é membro da organização não enxerga a projeção
reset role;
insert into auth.users (id, email, raw_user_meta_data) values ('22222222-2222-2222-2222-222222222222', 'bruno@teste.dev', '{"nome":"Bruno"}');
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ begin
  begin
    perform public.projecao_contratos((select org from r), (select mes_seguinte from r), (select mes_seguinte from r));
    raise exception 'T7 não-membro deveria ser bloqueado';
  exception when insufficient_privilege then null; end;
end $$;

rollback;
\echo OK
