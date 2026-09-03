-- Verificação da migration 0023 (portal do cliente). Somente leitura. Esperado: 6 de 6 OK.
with checks as (
  select 'tabelas do portal (5)' item, (select count(*) from pg_tables where schemaname='public' and tablename in ('portal_config','portal_acessos','promocoes','indicacoes','descontos_contrato')) = 5 ok
  union all select 'RLS nas 5 tabelas', (select bool_and(relrowsecurity) from pg_class where oid in ('public.portal_config'::regclass,'public.portal_acessos'::regclass,'public.promocoes'::regclass,'public.indicacoes'::regclass,'public.descontos_contrato'::regclass))
  union all select 'funções portal_* (12)', (select count(*) from pg_proc where proname in ('portal_pessoa','portal_vincular','portal_resumo','portal_faturas','portal_proximas_faturas','portal_pagamentos','portal_contratos','portal_promocoes','portal_indicacoes','portal_indicar','portal_indicacao_publica','portal_info_indicacao')) = 12
  union all select 'converter_indicacao e faturar_contrato com desconto', exists (select 1 from pg_proc where proname='converter_indicacao') and exists (select 1 from pg_proc p where p.proname='faturar_contrato' and pg_get_functiondef(p.oid) like '%descontos_contrato%')
  union all select 'anon só nas duas funções públicas', (select count(*) from information_schema.routine_privileges where grantee='anon' and routine_name like 'portal_%') = 2
  union all select 'novo usuário com portal=true não cria organização', exists (select 1 from pg_proc p where p.proname='tg_novo_usuario' and pg_get_functiondef(p.oid) like '%portal%')
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
