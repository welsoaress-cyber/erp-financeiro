-- Verificação da migration 0009 (faturamento). Somente leitura. Esperado: 7 de 7 OK.
with checks as (
  select 'tabelas faturamentos e faturamento_execucoes' item, (select count(*) from pg_tables where schemaname='public' and tablename in ('faturamentos','faturamento_execucoes')) = 2 ok
  union all select 'origem faturamento no enum', exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typname='origem_lancamento' and e.enumlabel='faturamento')
  union all select 'colunas de configuração (negócio e contrato)', (select count(*) from information_schema.columns where table_schema='public' and ((table_name='negocios' and column_name in ('conta_padrao_id','categoria_receita_id')) or (table_name='contratos' and column_name in ('faturamento_automatico','faturar_desde','conta_id')))) = 5
  union all select 'funções do motor de faturamento', (select count(*) from pg_proc where proname in ('competencias_pendentes','faturar_contrato','gerar_faturamento','gerar_faturamento_agora','gerar_faturamento_todas','data_vencimento_no_mes')) = 6
  union all select 'RLS + somente leitura para clientes', (select bool_and(relrowsecurity) from pg_class where oid in ('public.faturamentos'::regclass,'public.faturamento_execucoes'::regclass)) and not exists (select 1 from information_schema.role_table_grants where table_name in ('faturamentos','faturamento_execucoes') and (grantee='anon' or (grantee='authenticated' and privilege_type<>'SELECT')))
  union all select 'triggers de proteção/config/auditoria', (select count(*) from pg_trigger where tgname in ('faturamentos_protecao','faturamentos_auditoria','negocios_config','contratos_a_config')) = 4
  union all select 'view vw_faturamentos', exists (select 1 from pg_views where viewname='vw_faturamentos')
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
