-- Diagnóstico do esquema em produção. SOMENTE LEITURA. Cole o resultado inteiro no chat.
select 'tabela' as tipo, t.tablename as nome,
       (select string_agg(c.column_name || ':' || c.data_type, ', ' order by c.ordinal_position)
          from information_schema.columns c where c.table_schema = 'public' and c.table_name = t.tablename) as detalhe
  from pg_tables t where t.schemaname = 'public'
union all
select 'funcao', p.proname, pg_get_function_identity_arguments(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
union all
select 'trigger', tg.tgname, tg.tgrelid::regclass::text || ' -> ' || tg.tgfoid::regproc::text
  from pg_trigger tg where not tg.tgisinternal and tg.tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)
union all
select 'view', v.viewname, '' from pg_views v where v.schemaname = 'public'
union all
select 'policy', pol.policyname, pol.tablename::text from pg_policies pol where pol.schemaname = 'public'
union all
select 'enum', ty.typname, (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e where e.enumtypid = ty.oid)
  from pg_type ty where ty.typnamespace = 'public'::regnamespace and ty.typtype = 'e'
order by 1, 2;
