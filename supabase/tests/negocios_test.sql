-- Testes da migration 0006 (negócios). Saída final "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('22222222-2222-2222-2222-222222222222', 'bruno@teste.dev', '{"nome":"Bruno"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.negocios (organizacao_id, nome, slug) select organizacao_id, 'SERVNET', 'servnet' from public.categorias limit 1;
insert into public.negocios (organizacao_id, nome, slug) select organizacao_id, 'Servidor', 'servidor' from public.categorias limit 1;
insert into public.contas (organizacao_id, nome, tipo, saldo_inicial) select organizacao_id, 'Banco', 'corrente', 1000 from public.categorias limit 1;
insert into public.contas (organizacao_id, nome, tipo, saldo_inicial, negocio_id) select organizacao_id, 'Conta SERVNET', 'corrente', 500, (select id from public.negocios where slug = 'servnet') from public.categorias limit 1;

create temp table ids as
select (select id from public.negocios where slug = 'servnet') as servnet,
       (select id from public.negocios where slug = 'servidor') as servidor,
       (select id from public.contas where nome = 'Banco') as banco,
       (select id from public.contas where nome = 'Conta SERVNET') as conta_servnet,
       (select organizacao_id from public.negocios limit 1) as org,
       (select id from public.categorias where nome = 'Salário') as cat_sal,
       (select id from public.categorias where nome = 'Alimentação') as cat_alim;

-- T1: validações de negócio (slug, nome único, slug único)
do $$
declare v_org uuid;
begin
  select org into v_org from ids;
  begin
    insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'X', 'Slug Inválido');
    raise exception 'T1 slug inválido deveria falhar';
  exception when check_violation then null; end;
  begin
    insert into public.negocios (organizacao_id, nome, slug) values (v_org, ' servnet ', 'outro');
    raise exception 'T1 nome duplicado deveria falhar';
  exception when unique_violation then null; end;
  begin
    insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'Outro', 'servnet');
    raise exception 'T1 slug duplicado deveria falhar';
  exception when unique_violation then null; end;
end $$;

-- T2: lançamentos com negócio; pessoal sem negócio; transferência com negócio permitida
select public.criar_lancamento('receita', 'Mensalidade cliente', 100, '2026-09-10', null, '2026-09-10', conta_servnet, null, cat_sal, null, servnet) from ids;
select public.criar_lancamento('despesa', 'Link dedicado', 40, '2026-09-11', null, '2026-09-11', conta_servnet, null, cat_alim, null, servnet) from ids;
select public.criar_lancamento('receita', 'Salário', 3000, '2026-09-05', null, '2026-09-05', banco, null, cat_sal) from ids;
select public.criar_lancamento('transferencia', 'Aporte', 200, '2026-09-12', null, '2026-09-12', banco, conta_servnet, null, null, servnet) from ids;
do $$
declare r record; n int;
begin
  select * into r from public.vw_resultado_mensal_negocio where negocio_id = (select servnet from ids) and mes = '2026-09-01';
  assert r.receitas = 100 and r.despesas = 40 and r.resultado = 60, 'T2 resultado servnet';
  select * into r from public.vw_resultado_mensal_negocio where negocio_id is null and mes = '2026-09-01';
  assert r.receitas = 3000 and r.despesas = 0, 'T2 resultado pessoal';
  select * into r from public.vw_resultado_mensal where mes = '2026-09-01';
  assert r.receitas = 3100 and r.despesas = 40, 'T2 consolidado inalterado';
  select count(*) into n from public.vw_saldo_contas where negocio_id = (select servnet from ids) and saldo = 500 + 100 - 40 + 200; assert n = 1, 'T2 saldo conta do negócio';
end $$;

-- T3: negócio de outra organização ou inativo rejeitado; editar troca de negócio
do $$
declare v_id uuid;
begin
  select id into v_id from public.lancamentos where descricao = 'Link dedicado';
  perform public.atualizar_lancamento(v_id, 'Link dedicado', 40, '2026-09-11', null, '2026-09-11', null, null, null, null, (select servidor from ids));
  assert (select negocio_id from public.lancamentos where id = v_id) = (select servidor from ids), 'T3 trocar negócio';
  perform public.atualizar_lancamento(v_id, 'Link dedicado', 40, '2026-09-11', null, '2026-09-11', null, null, null, null, null);
  assert (select negocio_id from public.lancamentos where id = v_id) is null, 'T3 remover negócio';
  update public.negocios set ativo = false where slug = 'servidor';
  begin
    perform public.criar_lancamento('despesa', 'x', 1, '2026-09-11', null, '2026-09-11', (select banco from ids), null, (select cat_alim from ids), null, (select servidor from ids));
    raise exception 'T3 negócio inativo deveria falhar';
  exception when check_violation then null; end;
  update public.negocios set ativo = true where slug = 'servidor';
end $$;

-- T4: inativar bloqueado com previstos pendentes ou contas ativas; liberado depois
select public.criar_lancamento('despesa', 'Energia', 90, '2026-09-25', '2026-09-25', null, conta_servnet, null, cat_alim, null, servnet) from ids;
do $$
declare v_prev uuid;
begin
  begin
    update public.negocios set ativo = false where slug = 'servnet';
    raise exception 'T4 inativar com previsto deveria falhar';
  exception when check_violation then null; end;
  select id into v_prev from public.lancamentos where descricao = 'Energia';
  perform public.excluir_lancamento(v_prev);
  begin
    update public.negocios set ativo = false where slug = 'servnet';
    raise exception 'T4 inativar com conta ativa deveria falhar';
  exception when check_violation then null; end;
  -- desvincula a conta do negócio (conta com movimentos não inativa, mas pode mudar de negócio)
  update public.contas set negocio_id = null where nome = 'Conta SERVNET';
  update public.negocios set ativo = false where slug = 'servnet'; -- histórico efetivado não impede
  assert not (select ativo from public.negocios where slug = 'servnet'), 'T4 inativado com histórico';
  begin
    update public.contas set negocio_id = (select servnet from ids) where nome = 'Banco';
    raise exception 'T4 vincular conta a negócio inativo deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T5: RLS e delete
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
declare n int; v_org uuid;
begin
  select count(*) into n from public.negocios; assert n = 0, 'T5 select alheio';
  select count(*) into n from public.vw_resultado_mensal_negocio; assert n = 0, 'T5 view alheia';
  reset role; select org into v_org from ids; set local role authenticated;
  begin
    insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'Invasao', 'invasao');
    raise exception 'T5 insert alheio deveria falhar';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.negocios;
    raise exception 'T5 delete deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
-- T6: auditoria
do $$ declare n int; begin
  select count(*) into n from public.auditoria where tabela = 'negocios' and acao = 'INSERT'; assert n = 2, 'T6 auditoria';
end $$;

reset role;
rollback;
\echo OK
