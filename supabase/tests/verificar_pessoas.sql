-- Verificação da migration 0007 (pessoas e vínculos). Somente leitura. Esperado: 7 de 7 OK.
with checks as (
  select 'tabelas pessoas e pessoa_negocio_vinculos' item, (select count(*) from pg_tables where schemaname='public' and tablename in ('pessoas','pessoa_negocio_vinculos')) = 2 ok
  union all select 'tipos tipo_pessoa e papel_vinculo', (select count(*) from pg_type where typname in ('tipo_pessoa','papel_vinculo')) = 2
  union all select 'função documento_valido (CPF/CNPJ)', public.documento_valido('52998224725') and public.documento_valido('11222333000181') and not public.documento_valido('12345678900')
  union all select 'coluna pessoa_id em lancamentos', exists (select 1 from information_schema.columns where table_name='lancamentos' and column_name='pessoa_id')
  union all select 'RLS + policies sem delete nas duas tabelas', (select bool_and(relrowsecurity) from pg_class where oid in ('public.pessoas'::regclass,'public.pessoa_negocio_vinculos'::regclass)) and (select count(*) from pg_policies where tablename in ('pessoas','pessoa_negocio_vinculos')) = 6 and not exists (select 1 from information_schema.role_table_grants where table_name in ('pessoas','pessoa_negocio_vinculos') and (grantee='anon' or (grantee='authenticated' and privilege_type='DELETE')))
  union all select 'triggers de proteção/auditoria', (select count(*) from pg_trigger where tgname in ('pessoas_protecao','pessoas_auditoria','pessoas_atualizado_em','vinculos_protecao','vinculos_auditoria','vinculos_atualizado_em','lancamentos_pessoa')) = 7
  union all select 'motor com p_pessoa_id (12 parâmetros)', (select count(*) from pg_proc where proname in ('criar_lancamento','atualizar_lancamento') and pronargs >= 12) = 2 and (select count(*) from pg_proc where proname in ('criar_lancamento','atualizar_lancamento')) = 2
)
select item, ok, case when ok then 'PASS' else 'FALHOU' end as resultado from checks
union all select '== TOTAL ==', bool_and(ok), count(*) filter (where ok) || ' de ' || count(*) || ' verificações OK' from checks
order by 1;
