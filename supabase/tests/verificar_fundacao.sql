-- Verificação da Fundação no projeto Supabase real.
-- Como usar: SQL Editor do painel → colar → Run. Todas as linhas devem mostrar ok = true.
-- Somente leitura: não altera nada.
with checks as (
  select 'tabela organizacoes' item, exists (select 1 from pg_tables where schemaname='public' and tablename='organizacoes') ok
  union all select 'tabela organizacao_membros', exists (select 1 from pg_tables where schemaname='public' and tablename='organizacao_membros')
  union all select 'tabela auditoria', exists (select 1 from pg_tables where schemaname='public' and tablename='auditoria')
  union all select 'tipo papel_membro', exists (select 1 from pg_type where typname='papel_membro')
  union all select 'RLS organizacoes', (select relrowsecurity from pg_class where oid='public.organizacoes'::regclass)
  union all select 'RLS organizacao_membros', (select relrowsecurity from pg_class where oid='public.organizacao_membros'::regclass)
  union all select 'RLS auditoria', (select relrowsecurity from pg_class where oid='public.auditoria'::regclass)
  union all select 'policy organizacoes_select', exists (select 1 from pg_policies where policyname='organizacoes_select')
  union all select 'policy organizacoes_update', exists (select 1 from pg_policies where policyname='organizacoes_update')
  union all select 'policy organizacao_membros_select', exists (select 1 from pg_policies where policyname='organizacao_membros_select')
  union all select 'policy auditoria_select', exists (select 1 from pg_policies where policyname='auditoria_select')
  union all select 'sem policy de escrita em auditoria', not exists (select 1 from pg_policies where tablename='auditoria' and cmd<>'SELECT')
  union all select 'sem policy de insert/delete em organizacoes', not exists (select 1 from pg_policies where tablename='organizacoes' and cmd in ('INSERT','DELETE'))
  union all select 'função tg_auditoria (security definer)', exists (select 1 from pg_proc where proname='tg_auditoria' and prosecdef)
  union all select 'função tg_novo_usuario (security definer)', exists (select 1 from pg_proc where proname='tg_novo_usuario' and prosecdef)
  union all select 'função minhas_organizacoes (security definer)', exists (select 1 from pg_proc where proname='minhas_organizacoes' and prosecdef)
  union all select 'função sou_proprietario (security definer)', exists (select 1 from pg_proc where proname='sou_proprietario' and prosecdef)
  union all select 'função tg_atualizado_em', exists (select 1 from pg_proc where proname='tg_atualizado_em')
  union all select 'funções com search_path fixo', not exists (
      select 1 from pg_proc where pronamespace='public'::regnamespace
        and proname in ('tg_auditoria','tg_novo_usuario','minhas_organizacoes','sou_proprietario','tg_atualizado_em')
        and (proconfig is null or not exists (select 1 from unnest(proconfig) c where c like 'search_path=%')))
  union all select 'trigger on_auth_user_created em auth.users', exists (select 1 from pg_trigger where tgname='on_auth_user_created' and tgrelid='auth.users'::regclass)
  union all select 'trigger organizacoes_auditoria', exists (select 1 from pg_trigger where tgname='organizacoes_auditoria')
  union all select 'trigger organizacao_membros_auditoria', exists (select 1 from pg_trigger where tgname='organizacao_membros_auditoria')
  union all select 'trigger organizacoes_atualizado_em', exists (select 1 from pg_trigger where tgname='organizacoes_atualizado_em')
  union all select 'anon sem privilégios nas 3 tabelas', not exists (
      select 1 from information_schema.role_table_grants
      where grantee='anon' and table_schema='public' and table_name in ('organizacoes','organizacao_membros','auditoria'))
  union all select 'authenticated sem INSERT/DELETE em auditoria', not exists (
      select 1 from information_schema.role_table_grants
      where grantee='authenticated' and table_schema='public' and table_name='auditoria' and privilege_type in ('INSERT','UPDATE','DELETE'))
  union all select 'authenticated sem INSERT/DELETE em organizacoes', not exists (
      select 1 from information_schema.role_table_grants
      where grantee='authenticated' and table_schema='public' and table_name='organizacoes' and privilege_type in ('INSERT','DELETE'))
  union all select 'anon sem execute em minhas_organizacoes', not has_function_privilege('anon','public.minhas_organizacoes()','execute')
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all
select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
