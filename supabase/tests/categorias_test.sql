-- Testes da migration 0004 (categorias). Saída final "OK".
\set ON_ERROR_STOP on
begin;

-- Ana existia antes da migration (backfill); Bruno é criado depois (trigger de signup)
insert into auth.users (id, email, raw_user_meta_data) values
  ('22222222-2222-2222-2222-222222222222', 'bruno@teste.dev', '{"nome":"Bruno"}');

-- T1: categorias padrão para organização antiga (backfill) e nova (signup)
do $$
declare n int;
begin
  select count(*) into n from public.categorias c join public.organizacao_membros m on m.organizacao_id = c.organizacao_id
    where m.usuario_id = '11111111-1111-1111-1111-111111111111'; assert n = 11, 'T1 backfill Ana';
  select count(*) into n from public.categorias c join public.organizacao_membros m on m.organizacao_id = c.organizacao_id
    where m.usuario_id = '22222222-2222-2222-2222-222222222222'; assert n = 11, 'T1 signup Bruno';
  select count(*) into n from public.categorias where tipo = 'receita' and nome = 'Salário'; assert n = 2, 'T1 conteúdo';
end $$;

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- T2: RLS — Ana vê só as suas 11
do $$ declare n int; begin
  select count(*) into n from public.categorias; assert n = 11, 'T2 rls select';
end $$;

-- T3: criar subcategoria válida; unicidade por tipo ignorando maiúsculas; "Outros" existe nos dois tipos
insert into public.categorias (organizacao_id, nome, tipo, categoria_pai_id)
  select organizacao_id, 'Supermercado', 'despesa', id from public.categorias where nome = 'Alimentação';
do $$
declare v_org uuid; v_alim uuid; v_sal uuid;
begin
  select organizacao_id, id into v_org, v_alim from public.categorias where nome = 'Alimentação';
  select id into v_sal from public.categorias where nome = 'Salário';
  begin
    insert into public.categorias (organizacao_id, nome, tipo) values (v_org, ' alimentação ', 'despesa');
    raise exception 'T3 duplicada deveria falhar';
  exception when unique_violation then null; end;
  -- pai de tipo diferente
  begin
    insert into public.categorias (organizacao_id, nome, tipo, categoria_pai_id) values (v_org, 'Bônus', 'receita', v_alim);
    raise exception 'T3 pai de outro tipo deveria falhar';
  exception when check_violation then null; end;
  -- 3º nível
  begin
    insert into public.categorias (organizacao_id, nome, tipo, categoria_pai_id)
      select v_org, 'Padaria', 'despesa', id from public.categorias where nome = 'Supermercado';
    raise exception 'T3 terceiro nível deveria falhar';
  exception when check_violation then null; end;
  -- tipo imutável
  begin
    update public.categorias set tipo = 'receita' where id = v_alim;
    raise exception 'T3 mudar tipo deveria falhar';
  exception when check_violation then null; end;
  -- categoria com filhas não pode virar subcategoria
  begin
    update public.categorias set categoria_pai_id = (select id from public.categorias where nome = 'Moradia') where id = v_alim;
    raise exception 'T3 pai com filhas virar sub deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T4: inativar com subcategoria ativa bloqueado; inativar sub e depois pai funciona; reativar sub com pai inativo bloqueado
do $$
declare v_alim uuid; v_sup uuid;
begin
  select id into v_alim from public.categorias where nome = 'Alimentação';
  select id into v_sup  from public.categorias where nome = 'Supermercado';
  begin
    update public.categorias set ativo = false where id = v_alim;
    raise exception 'T4 inativar com sub ativa deveria falhar';
  exception when check_violation then null; end;
  update public.categorias set ativo = false where id = v_sup;
  update public.categorias set ativo = false where id = v_alim;
  begin
    update public.categorias set ativo = true where id = v_sup;
    raise exception 'T4 reativar sub com pai inativo deveria falhar';
  exception when check_violation then null; end;
  update public.categorias set ativo = true where id = v_alim;
  update public.categorias set ativo = true where id = v_sup;
end $$;

-- T5: editar nome e trocar pai (mesmo tipo) funciona
update public.categorias set nome = 'Mercado', categoria_pai_id = (select id from public.categorias where nome = 'Moradia')
  where nome = 'Supermercado';
do $$ declare n int; begin
  select count(*) into n from public.categorias c join public.categorias p on p.id = c.categoria_pai_id
    where c.nome = 'Mercado' and p.nome = 'Moradia'; assert n = 1, 'T5 editar';
end $$;

-- T6: delete negado; outro usuário não cria na organização alheia
do $$ begin
  begin
    delete from public.categorias;
    raise exception 'T6 delete deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
declare v_org_ana uuid;
begin
  reset role;
  select organizacao_id into v_org_ana from public.organizacao_membros where usuario_id = '11111111-1111-1111-1111-111111111111';
  set local role authenticated;
  begin
    insert into public.categorias (organizacao_id, nome, tipo) values (v_org_ana, 'Invasao', 'despesa');
    raise exception 'T6 insert alheio deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- T7: com lançamentos reais (motor da Etapa 5), inativar bloqueado; renomear permitido
insert into public.contas (organizacao_id, nome, tipo) select organizacao_id, 'Conta teste', 'dinheiro' from public.categorias where nome = 'Mercado';
select public.criar_lancamento('despesa', 'Compra teste', 10, '2026-09-01', null, '2026-09-01',
  (select id from public.contas where nome = 'Conta teste'), null, (select id from public.categorias where nome = 'Mercado'));
do $$ begin
  begin
    update public.categorias set ativo = false where nome = 'Mercado';
    raise exception 'T7 inativar com lançamentos deveria falhar';
  exception when check_violation then null; end;
  update public.categorias set nome = 'Mercado Semanal' where nome = 'Mercado';
end $$;

-- T8: auditoria
do $$ declare n int; begin
  select count(*) into n from public.auditoria where tabela = 'categorias' and acao = 'INSERT' and usuario_id = '11111111-1111-1111-1111-111111111111'; assert n = 1, 'T8 insert';
  select count(*) into n from public.auditoria where tabela = 'categorias' and acao = 'UPDATE'; assert n >= 6, 'T8 updates';
end $$;

reset role;
rollback;
\echo OK
