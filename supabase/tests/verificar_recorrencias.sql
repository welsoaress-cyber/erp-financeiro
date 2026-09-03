-- Verificação da migration 0012 (recorrências). Somente leitura. Esperado: 6 de 6 OK.
with checks as (
  select 'colunas de recorrência em lancamentos' item, (select count(*) from information_schema.columns where table_schema='public' and table_name='lancamentos' and column_name in ('recorrente','periodicidade','numero_parcelas','parcela_atual','data_fim_recorrencia','lancamento_origem_id')) = 6 ok
  union all select 'enum periodicidade_recorrencia (6 valores)', (select count(*) from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='periodicidade_recorrencia') = 6
  union all select 'trigger lancamentos_b_recorrencia', exists (select 1 from pg_trigger where tgname='lancamentos_b_recorrencia')
  union all select 'funções do motor (gerar_proxima_parcela, proxima_data_recorrencia)', (select count(*) from pg_proc where proname in ('gerar_proxima_parcela','proxima_data_recorrencia')) = 2
  union all select 'criar/atualizar_lancamento com 17 parâmetros', (select count(*) from pg_proc where proname in ('criar_lancamento','atualizar_lancamento') and pronargs = 17) = 2
  union all select 'gerar_proxima_parcela sem execute para authenticated/anon', not exists (select 1 from information_schema.routine_privileges where routine_name='gerar_proxima_parcela' and grantee in ('anon','authenticated','PUBLIC'))
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
