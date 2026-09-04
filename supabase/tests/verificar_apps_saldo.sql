-- Verificação das migrations 0013 + 0030 (carteira de ativação de apps, dois saldos). Somente leitura. Esperado: 7 de 7 OK.
with checks as (
  select 'negocios.usa_carteira (sem tipo_saldo/taxa_conversao)' item, exists (select 1 from information_schema.columns where table_schema='public' and table_name='negocios' and column_name='usa_carteira' and data_type='boolean')
    and (select count(*) from information_schema.columns where table_schema='public' and table_name='negocios' and column_name in ('tipo_saldo','taxa_conversao')) = 0 ok
  union all select 'carteira com saldo_dinheiro e saldo_credito', (select count(*) from information_schema.columns where table_schema='public' and table_name='carteira' and column_name in ('saldo_dinheiro','saldo_credito')) = 2
  union all select 'tabelas carteira, transacoes_carteira, apps_catalogo', (select count(*) from pg_tables where schemaname='public' and tablename in ('carteira','transacoes_carteira','apps_catalogo')) = 3
  union all select 'RLS nas 3 tabelas', (select bool_and(relrowsecurity) from pg_class where oid in ('public.carteira'::regclass,'public.transacoes_carteira'::regclass,'public.apps_catalogo'::regclass))
  union all select 'sem insert/delete para clientes (só motor)', not exists (select 1 from information_schema.role_table_grants where table_name in ('carteira','transacoes_carteira','apps_catalogo') and (grantee='anon' or (grantee='authenticated' and privilege_type in ('INSERT','DELETE'))))
  union all select 'funções do motor da carteira', (select count(*) from pg_proc where proname in ('configurar_carteira','criar_app','recarregar_carteira','ativar_app')) = 4
  union all select 'views vw_carteira_resumo e vw_contratos_app', (select count(*) from pg_views where viewname in ('vw_carteira_resumo','vw_contratos_app')) = 2
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
