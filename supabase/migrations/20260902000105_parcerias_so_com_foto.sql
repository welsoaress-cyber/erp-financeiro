-- =============================================================================
-- 0105 · Ajuste da 0103 — Portal só mostra parceria com foto, e mostra a foto
-- =============================================================================
-- Decisão do proprietário: com ~500 parceiros só em texto a tela ficou poluída
-- e sem graça. Agora só aparece pro cliente quem tem pelo menos 1 foto salva
-- (as mesmas 3 guardadas pelo admin pra divulgar no Instagram/WhatsApp — antes
-- eram só uso interno, agora aparecem pro cliente também).
-- =============================================================================

drop function public.portal_parcerias(uuid);
create function public.portal_parcerias(p_negocio_id uuid)
returns table (id uuid, nome text, tipo text, beneficio text, categoria text, cobertura text, origem public.origem_parceria, foto1 text, foto2 text, foto3 text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.nome, p.tipo, p.beneficio, p.categoria, p.cobertura, p.origem, p.foto1, p.foto2, p.foto3
    from public.parcerias p
   where p.negocio_id = p_negocio_id and p.ativo and (p.foto1 is not null or p.foto2 is not null or p.foto3 is not null)
   order by p.categoria nulls last, p.nome;
$$;
revoke all on function public.portal_parcerias(uuid) from public, anon;
grant execute on function public.portal_parcerias(uuid) to authenticated;
