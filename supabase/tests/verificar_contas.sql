-- Verificação da migration 0002 (contas) no projeto real. Somente leitura. Esperado: 9 de 9 OK.
with checks as (
  select 'tabela contas' item, exists (select 1 from pg_tables where schemaname='public' and tablename='contas') ok
  union all select 'tipo tipo_conta', exists (select 1 from pg_type where typname='tipo_conta')
  union all select 'RLS contas', (select relrowsecurity from pg_class where oid='public.contas'::regclass)
  union all select 'policies select/insert/update, sem delete', (select count(*) from pg_policies where tablename='contas') = 3 and not exists (select 1 from pg_policies where tablename='contas' and cmd='DELETE')
  union all select 'authenticated sem DELETE em contas', not exists (select 1 from information_schema.role_table_grants where grantee='authenticated' and table_name='contas' and privilege_type='DELETE')
  union all select 'anon sem privilégios em contas', not exists (select 1 from information_schema.role_table_grants where grantee='anon' and table_name='contas')
  union all select 'função conta_possui_movimentos', exists (select 1 from pg_proc where proname='conta_possui_movimentos' and prosecdef)
  union all select 'triggers protecao/atualizado_em/auditoria', (select count(*) from pg_trigger where tgrelid='public.contas'::regclass and tgname in ('contas_protecao','contas_atualizado_em','contas_auditoria')) = 3
  union all select 'índice único de nome por organização', exists (select 1 from pg_indexes where tablename='contas' and indexname='contas_nome_unico_idx')
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
