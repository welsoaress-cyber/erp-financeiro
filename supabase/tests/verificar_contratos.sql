-- Verificação da migration 0008 (planos e contratos). Somente leitura. Esperado: 7 de 7 OK.
with checks as (
  select 'tabelas planos e contratos' item, (select count(*) from pg_tables where schemaname='public' and tablename in ('planos','contratos')) = 2 ok
  union all select 'tipos periodicidade e status_contrato', (select count(*) from pg_type where typname in ('periodicidade','status_contrato')) = 2
  union all select 'coluna contrato_id em lancamentos', exists (select 1 from information_schema.columns where table_name='lancamentos' and column_name='contrato_id')
  union all select 'RLS + policies sem delete', (select bool_and(relrowsecurity) from pg_class where oid in ('public.planos'::regclass,'public.contratos'::regclass)) and (select count(*) from pg_policies where tablename in ('planos','contratos')) = 6 and not exists (select 1 from information_schema.role_table_grants where table_name in ('planos','contratos') and (grantee='anon' or (grantee='authenticated' and privilege_type='DELETE')))
  union all select 'triggers de proteção/vínculo/auditoria', (select count(*) from pg_trigger where tgname in ('planos_protecao','planos_auditoria','planos_atualizado_em','contratos_protecao','contratos_vinculo','contratos_auditoria','contratos_atualizado_em','lancamentos_a_contrato')) = 8
  union all select 'motor com p_contrato_id (13 parâmetros)', (select count(*) from pg_proc where proname in ('criar_lancamento','atualizar_lancamento') and pronargs >= 13) = 2 and (select count(*) from pg_proc where proname in ('criar_lancamento','atualizar_lancamento')) = 2
  union all select 'views vw_resultado_por_contrato e vw_receita_recorrente', (select count(*) from pg_views where viewname in ('vw_resultado_por_contrato','vw_receita_recorrente')) = 2
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
