-- =============================================================================
-- 0043 · Clientes do servidor: o "nome" importado é o login
-- =============================================================================
-- Regra do proprietário: cliente de servidor normalmente não tem nome — só
-- login. A importação da planilha gravou o login no campo nome; este backfill
-- copia para pessoas.login_servidor todo nome sem espaço no formato de login,
-- para o módulo Disparos casar o PDF sem vínculo manual. Nome fica como está
-- (o proprietário completa o nome real quando quiser, sem perder o vínculo).
-- =============================================================================

with candidatas as (
  select distinct on (organizacao_id, lower(btrim(nome))) id, organizacao_id, btrim(nome) as login
    from public.pessoas
   where login_servidor is null
     and btrim(nome) ~ '^[A-Za-z0-9._@-]{2,60}$'
   order by organizacao_id, lower(btrim(nome)), criado_em
)
update public.pessoas p
   set login_servidor = c.login
  from candidatas c
 where p.id = c.id
   and not exists (
     select 1 from public.pessoas p2
      where p2.organizacao_id = c.organizacao_id
        and lower(p2.login_servidor) = lower(c.login)
   );
