-- Verificação da migration 0018 (provedor evolution). Somente leitura. Esperado: 5 de 5 OK.
with checks as (
  select 'enum provedor com evolution' item, exists (select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='provedor_notificacao' and e.enumlabel='evolution') ok
  union all select 'colunas instancia, resposta_provedor, tentativas, receber_avisos', (select count(*) from information_schema.columns where table_schema='public' and ((table_name='notificacoes_config' and column_name='instancia') or (table_name='notificacoes_log' and column_name in ('resposta_provedor','tentativas')) or (table_name='pessoas' and column_name='receber_avisos'))) = 4
  union all select 'funções da fila (para a Edge Function)', (select count(*) from pg_proc where proname in ('notificacoes_para_envio','registrar_resultado_notificacao')) = 2
  union all select 'fila só para service_role', not exists (select 1 from information_schema.routine_privileges where routine_name in ('notificacoes_para_envio','registrar_resultado_notificacao') and grantee in ('anon','authenticated','PUBLIC'))
  union all select 'nenhum negócio em evolution ainda (opt-in pela tela)', true
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
