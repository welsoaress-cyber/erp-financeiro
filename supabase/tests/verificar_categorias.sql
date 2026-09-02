-- Verificação da migration 0004 (categorias) no projeto real. Somente leitura. Esperado: 9 de 9 OK.
with checks as (
  select 'tabela categorias' item, exists (select 1 from pg_tables where schemaname='public' and tablename='categorias') ok
  union all select 'tipo tipo_categoria', exists (select 1 from pg_type where typname='tipo_categoria')
  union all select 'RLS categorias', (select relrowsecurity from pg_class where oid='public.categorias'::regclass)
  union all select 'policies select/insert/update, sem delete', (select count(*) from pg_policies where tablename='categorias') = 3 and not exists (select 1 from pg_policies where tablename='categorias' and cmd='DELETE')
  union all select 'anon sem privilégios / authenticated sem DELETE', not exists (select 1 from information_schema.role_table_grants where table_name='categorias' and (grantee='anon' or (grantee='authenticated' and privilege_type='DELETE')))
  union all select 'funções categoria_possui_lancamentos e criar_categorias_padrao', (select count(*) from pg_proc where proname in ('categoria_possui_lancamentos','criar_categorias_padrao')) = 2
  union all select 'triggers protecao/atualizado_em/auditoria', (select count(*) from pg_trigger where tgrelid='public.categorias'::regclass and tgname in ('categorias_protecao','categorias_atualizado_em','categorias_auditoria')) = 3
  union all select 'índice único nome por organização e tipo', exists (select 1 from pg_indexes where tablename='categorias' and indexname='categorias_nome_unico_idx')
  union all select 'toda organização tem as 11 categorias padrão', not exists (select 1 from public.organizacoes o where (select count(*) from public.categorias c where c.organizacao_id = o.id and c.categoria_pai_id is null) < 11)
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
