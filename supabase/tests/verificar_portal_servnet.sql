-- Verificação da migration 0024 (portal estilo SERVNET). Somente leitura. Esperado: 6 de 6 OK.
with checks as (
  select 'tabelas novas (3) + colunas' item, (select count(*) from pg_tables where schemaname='public' and tablename in ('portal_status_rede','portal_solicitacoes','portal_login_tentativas')) = 3
      and exists (select 1 from information_schema.columns where table_name='pessoas' and column_name='data_nascimento')
      and (select count(*) from information_schema.columns where table_name='portal_config' and column_name in ('tema','whatsapp_suporte','beneficio_tipo','fidelidade_ativa','site_url')) = 5 ok
  union all select 'RLS nas 3 tabelas', (select bool_and(relrowsecurity) from pg_class where oid in ('public.portal_status_rede'::regclass,'public.portal_solicitacoes'::regclass,'public.portal_login_tentativas'::regclass))
  union all select 'fidelidade (cartão + prêmio) e faturar_contrato com mês grátis', (select count(*) from pg_proc where proname in ('fidelidade_cartao','fidelidade_registrar_premio')) = 2 and exists (select 1 from pg_proc p where p.proname='faturar_contrato' and pg_get_functiondef(p.oid) like '%Mês grátis%')
  union all select 'login sem senha só para service_role', (select count(*) from pg_proc where proname in ('portal_login_verificar','portal_vincular_servico')) = 2 and not exists (select 1 from information_schema.routine_privileges where routine_name in ('portal_login_verificar','portal_vincular_servico') and grantee in ('anon','authenticated','PUBLIC'))
  union all select 'funções do cliente (5)', (select count(*) from pg_proc where proname in ('portal_status_rede','portal_fidelidade','portal_atualizar_contato','portal_solicitar','portal_solicitacoes_cliente')) = 5
  union all select 'anon continua só nas duas funções públicas', (select count(*) from information_schema.routine_privileges where grantee='anon' and routine_name like 'portal\_%') = 2
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
