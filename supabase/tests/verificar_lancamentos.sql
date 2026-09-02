-- Verificação da migration 0005 (motor) no projeto real. Somente leitura. Esperado: 8 de 8 OK.
with checks as (
  select 'tabelas lancamentos e movimentos' item, (select count(*) from pg_tables where schemaname='public' and tablename in ('lancamentos','movimentos')) = 2 ok
  union all select 'tipos tipo/status/origem_lancamento', (select count(*) from pg_type where typname in ('tipo_lancamento','status_lancamento','origem_lancamento')) = 3
  union all select 'RLS nas duas tabelas', (select bool_and(relrowsecurity) from pg_class where oid in ('public.lancamentos'::regclass, 'public.movimentos'::regclass))
  union all select 'cliente só lê (sem INSERT/UPDATE/DELETE)', not exists (select 1 from information_schema.role_table_grants where table_name in ('lancamentos','movimentos') and (grantee='anon' or (grantee='authenticated' and privilege_type<>'SELECT')))
  union all select '5 funções do motor', (select count(*) from pg_proc where proname in ('criar_lancamento','atualizar_lancamento','efetivar_lancamento','cancelar_lancamento','excluir_lancamento') and prosecdef) = 5
  union all select 'triggers de proteção e auditoria', (select count(*) from pg_trigger where tgname in ('lancamentos_protecao','lancamentos_auditoria','lancamentos_atualizado_em','movimentos_protecao','movimentos_auditoria')) = 5
  union all select 'views vw_saldo_contas e vw_resultado_mensal', (select count(*) from pg_views where schemaname='public' and viewname in ('vw_saldo_contas','vw_resultado_mensal')) = 2
  union all select 'integridade: nenhum efetivado sem movimento, nenhum não efetivado com movimento', not exists (
      select 1 from public.lancamentos l left join public.movimentos m on m.lancamento_id = l.id
      group by l.id, l.status having (l.status = 'efetivado') <> (count(m.id) > 0))
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
