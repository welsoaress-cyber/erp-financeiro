-- Testes da migration 0003 (auditoria de autenticação). Saída final "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data, encrypted_password) values
  ('11111111-1111-1111-1111-111111111111', 'ana@teste.dev', '{"nome":"Ana"}', 'hash1');

update auth.users set last_sign_in_at = now() where id = '11111111-1111-1111-1111-111111111111';
update auth.users set email = 'ana.nova@teste.dev' where id = '11111111-1111-1111-1111-111111111111';
update auth.users set encrypted_password = 'hash2' where id = '11111111-1111-1111-1111-111111111111';
update auth.users set raw_user_meta_data = '{"nome":"Ana B"}' where id = '11111111-1111-1111-1111-111111111111'; -- não auditado

do $$
declare n int; v_org uuid;
begin
  select organizacao_id into v_org from public.organizacao_membros where usuario_id = '11111111-1111-1111-1111-111111111111';
  select count(*) into n from public.auditoria where tabela = 'auth.users' and acao = 'LOGIN' and organizacao_id = v_org; assert n = 1, 'S1 login auditado';
  select count(*) into n from public.auditoria where tabela = 'auth.users' and acao = 'UPDATE'
    and dados_antes ->> 'email' = 'ana@teste.dev' and dados_depois ->> 'email' = 'ana.nova@teste.dev'; assert n = 1, 'S2 troca de e-mail auditada';
  select count(*) into n from public.auditoria where tabela = 'auth.users' and (dados_depois ->> 'senha_alterada')::boolean; assert n = 1, 'S3 troca de senha auditada';
  select count(*) into n from public.auditoria where tabela = 'auth.users' and (dados_depois::text like '%hash%' or coalesce(dados_antes::text,'') like '%hash%'); assert n = 0, 'S4 nenhum hash gravado';
  select count(*) into n from public.auditoria where tabela = 'auth.users'; assert n = 3, 'S5 metadata não gera auditoria';
end $$;

-- S6: o próprio usuário enxerga sua trilha de autenticação; outro usuário não
insert into auth.users (id, email) values ('22222222-2222-2222-2222-222222222222', 'bruno@teste.dev');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare n int; begin
  select count(*) into n from public.auditoria where tabela = 'auth.users'; assert n = 3, 'S6 vê a própria trilha';
end $$;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ declare n int; begin
  select count(*) into n from public.auditoria where tabela = 'auth.users'; assert n = 0, 'S6 não vê trilha alheia';
end $$;
reset role;
rollback;
\echo OK
