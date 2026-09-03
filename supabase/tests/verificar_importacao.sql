-- Verificação da migration 0011 (importação). Somente leitura. Esperado: 4 de 4 OK.
with checks as (
  select 'funções de importação' item, (select count(*) from pg_proc where proname in ('importar_clientes','nome_plano_importado','data_importada')) = 3 ok
  union all select 'importar_clientes com invoker (RLS vale)', exists (select 1 from pg_proc where proname='importar_clientes' and not prosecdef)
  union all select 'sem execute para anon/public', not exists (select 1 from information_schema.routine_privileges where routine_name in ('importar_clientes','nome_plano_importado','data_importada') and grantee in ('anon','PUBLIC'))
  union all select 'mapeamento de plano legado', public.nome_plano_importado('Velocidade_0100_MB') = 'Plano 100 Mbps'
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
