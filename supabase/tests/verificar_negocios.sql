-- Verificação da migration 0006 (negócios) no projeto real. Somente leitura. Esperado: 7 de 7 OK.
with checks as (
  select 'tabela negocios' item, exists (select 1 from pg_tables where schemaname='public' and tablename='negocios') ok
  union all select 'coluna negocio_id em lancamentos e contas', (select count(*) from information_schema.columns where table_schema='public' and column_name='negocio_id' and table_name in ('lancamentos','contas')) = 2
  union all select 'RLS negocios + policies sem delete', (select relrowsecurity from pg_class where oid='public.negocios'::regclass) and (select count(*) from pg_policies where tablename='negocios') = 3
  union all select 'anon sem privilégios / authenticated sem DELETE', not exists (select 1 from information_schema.role_table_grants where table_name='negocios' and (grantee='anon' or (grantee='authenticated' and privilege_type='DELETE')))
  union all select 'triggers negocios/contas/lancamentos', (select count(*) from pg_trigger where tgname in ('negocios_protecao','negocios_atualizado_em','negocios_auditoria','contas_negocio','lancamentos_negocio')) = 5
  union all select 'motor com p_negocio_id (11 parâmetros) e sem assinatura antiga', (select count(*) from pg_proc where proname in ('criar_lancamento','atualizar_lancamento') and pronargs = 11) = 2 and (select count(*) from pg_proc where proname in ('criar_lancamento','atualizar_lancamento')) = 2
  union all select 'views vw_resultado_mensal_negocio e vw_saldo_contas.negocio_id', exists (select 1 from pg_views where viewname='vw_resultado_mensal_negocio') and exists (select 1 from information_schema.columns where table_name='vw_saldo_contas' and column_name='negocio_id')
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
