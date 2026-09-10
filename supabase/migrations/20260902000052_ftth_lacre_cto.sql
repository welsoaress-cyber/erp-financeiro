-- =============================================================================
-- 0052 · FTTH: identificação física (lacre/etiqueta) da própria CTO
-- =============================================================================
-- Além do código lógico (CTO-001), a caixa em campo carrega uma etiqueta/lacre
-- numerado próprio. Único por organização; editável no cadastro da CTO.
-- =============================================================================

alter table public.ctos add column lacre text
  check (lacre is null or lacre ~ '^[A-Za-z0-9-]{3,20}$');
create unique index ctos_lacre_unico on public.ctos (organizacao_id, upper(lacre)) where lacre is not null;

-- view recriada com a coluna nova
drop view public.vw_ctos_ocupacao;
create view public.vw_ctos_ocupacao
with (security_invoker = true) as
select c.*,
       count(p.id) filter (where p.status = 'ocupada') as ocupadas,
       count(p.id) filter (where p.status = 'reservada') as reservadas,
       count(p.id) filter (where p.status = 'livre' and not p.defeito) as livres,
       count(p.id) filter (where p.defeito) as com_defeito,
       count(p.id) filter (where p.drop_disponivel and p.status = 'livre') as drops_disponiveis
  from public.ctos c
  left join public.cto_portas p on p.cto_id = c.id
 group by c.id;
revoke all on public.vw_ctos_ocupacao from public, anon;
grant select on public.vw_ctos_ocupacao to authenticated;
