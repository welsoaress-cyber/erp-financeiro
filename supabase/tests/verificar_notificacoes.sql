-- Verificação da migration 0016 (notificações). Somente leitura. Esperado: 6 de 6 OK.
with checks as (
  select 'tabelas notificacoes_config e notificacoes_log' item, (select count(*) from pg_tables where schemaname='public' and tablename in ('notificacoes_config','notificacoes_log')) = 2 ok
  union all select 'enums tipo/status/provedor', (select count(*) from pg_type where typname in ('tipo_notificacao','status_notificacao','provedor_notificacao')) = 3
  union all select 'funções do motor de notificações', (select count(*) from pg_proc where proname in ('gerar_notificacoes','processar_notificacoes','executar_notificacoes','executar_notificacoes_agora','executar_notificacoes_todas','enviar_notificacao_teste','renderizar_template','numero_e164','moeda_br')) = 9
  union all select 'RLS + log somente leitura para clientes', (select bool_and(relrowsecurity) from pg_class where oid in ('public.notificacoes_config'::regclass,'public.notificacoes_log'::regclass)) and not exists (select 1 from information_schema.role_table_grants where table_name='notificacoes_log' and (grantee='anon' or (grantee='authenticated' and privilege_type<>'SELECT')))
  union all select 'triggers de proteção/auditoria', (select count(*) from pg_trigger where tgname in ('notificacoes_config_protecao','notificacoes_config_auditoria','notificacoes_log_protecao','notificacoes_log_auditoria')) = 4
  union all select 'view vw_notificacoes', exists (select 1 from pg_views where viewname='vw_notificacoes')
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
