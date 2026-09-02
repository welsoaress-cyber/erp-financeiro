-- Verificação genérica de segurança: TODAS as tabelas do schema public.
-- Rodar após cada migration. Esperado: coluna ok = true em todas as linhas.
select
  c.relname as tabela,
  c.relrowsecurity as rls_ativo,
  (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) as policies,
  not exists (select 1 from information_schema.role_table_grants g
              where g.grantee = 'anon' and g.table_schema = 'public' and g.table_name = c.relname) as anon_sem_acesso,
  not exists (select 1 from information_schema.role_table_grants g
              where g.grantee = 'authenticated' and g.table_schema = 'public' and g.table_name = c.relname
                and g.privilege_type = 'DELETE') as sem_delete_cliente,
  exists (select 1 from pg_trigger t where t.tgrelid = c.oid and t.tgname like '%auditoria%') as auditoria,
  c.relrowsecurity
    and (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) > 0
    and not exists (select 1 from information_schema.role_table_grants g
                    where g.grantee = 'anon' and g.table_schema = 'public' and g.table_name = c.relname) as ok
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;
