-- =============================================================================
-- 0076 · Etapa 49D — Vitrine visível ao cliente logado (antes de indicar)
-- =============================================================================
-- O cliente do portal vê o catálogo de presentes na página "Indique e ganhe"
-- ANTES de ter indicação convertida — motivação para indicar. Mesmo conteúdo
-- da vitrine pública, resolvido pelo negócio do contrato ativo do cliente.
-- =============================================================================

create function public.portal_vitrine()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public.vitrine_publica(n.slug)
    from public.contratos c
    join public.negocios n on n.id = c.negocio_id
   where c.pessoa_id = public.portal_pessoa() and c.status <> 'encerrado'
   order by c.data_inicio desc
   limit 1;
$$;
revoke all on function public.portal_vitrine() from public, anon;
grant execute on function public.portal_vitrine() to authenticated;
