-- =============================================================================
-- 0051 · FTTH: lacre numerado por porta
-- =============================================================================
-- Dentro da CTO cada drop recebe um lacre plástico numerado (ex.: 0678901).
-- O número é gravado na porta, é único na organização e identifica o cliente
-- fisicamente na caixa.
-- =============================================================================

alter table public.cto_portas add column lacre text
  check (lacre is null or lacre ~ '^[A-Za-z0-9-]{3,20}$');
create unique index cto_portas_lacre_unico on public.cto_portas (organizacao_id, upper(lacre)) where lacre is not null;

create function public.lacre_porta_cto(p_porta_id uuid, p_lacre text)
returns public.cto_portas
language plpgsql
security definer
set search_path = public
as $$
declare pt public.cto_portas%rowtype;
begin
  select * into pt from public.cto_portas where id = p_porta_id;
  if not found then raise exception 'Porta não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(pt.organizacao_id);
  perform set_config('erp.motor', 'on', true);
  update public.cto_portas set lacre = nullif(upper(btrim(coalesce(p_lacre, ''))), '') where id = p_porta_id returning * into pt;
  return pt;
end;
$$;
revoke all on function public.lacre_porta_cto(uuid, text) from public, anon;
grant execute on function public.lacre_porta_cto(uuid, text) to authenticated;
