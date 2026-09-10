-- =============================================================================
-- 0048 · Etapa 27B — FTTH: POP, fios POP→CTO e localização dos clientes
-- =============================================================================
-- O POP é a central do provedor: um ponto da rede (mesma tabela ctos, tipo
-- 'pop'). Cada CTO pode apontar de qual POP vem sua fibra (pop_id) — o mapa
-- desenha o fio. Cada porta ocupada pode guardar a localização do cliente
-- (lat/long) — o mapa desenha o fio CTO→cliente com o nome. Traçado em linha
-- reta (sem vértices de poste nesta versão).
-- =============================================================================

create type public.tipo_ponto_rede as enum ('cto', 'pop');
alter table public.ctos add column tipo public.tipo_ponto_rede not null default 'cto';
alter table public.ctos add column pop_id uuid references public.ctos (id);
comment on column public.ctos.pop_id is 'POP de onde vem a fibra desta CTO (fio desenhado no mapa).';

create or replace function public.tg_ctos_pop()
returns trigger
language plpgsql
set search_path = public
as $$
declare p public.ctos%rowtype;
begin
  if new.tipo = 'pop' then
    new.pop_id := null; -- POP não pende de outro POP nesta versão
  elsif new.pop_id is not null then
    if new.pop_id = new.id then raise exception 'A CTO não pode apontar para ela mesma.' using errcode = 'check_violation'; end if;
    select * into p from public.ctos where id = new.pop_id;
    if not found or p.tipo <> 'pop' or p.negocio_id <> new.negocio_id then
      raise exception 'pop_id deve apontar para um POP do mesmo negócio.' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.tg_ctos_pop() from public, anon, authenticated;
create trigger ctos_a_pop before insert or update on public.ctos for each row execute function public.tg_ctos_pop();

-- localização do cliente na porta (para o fio CTO→cliente no mapa)
alter table public.cto_portas add column cliente_latitude numeric(9,6) check (cliente_latitude is null or cliente_latitude between -90 and 90);
alter table public.cto_portas add column cliente_longitude numeric(9,6) check (cliente_longitude is null or cliente_longitude between -180 and 180);

create function public.local_cliente_porta(p_porta_id uuid, p_latitude numeric, p_longitude numeric)
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
  if pt.status = 'livre' then raise exception 'Marque o local só em porta com cliente.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.cto_portas set cliente_latitude = p_latitude, cliente_longitude = p_longitude where id = p_porta_id returning * into pt;
  return pt;
end;
$$;
revoke all on function public.local_cliente_porta(uuid, numeric, numeric) from public, anon;
grant execute on function public.local_cliente_porta(uuid, numeric, numeric) to authenticated;

-- a view de ocupação ganha as colunas novas (recriada por segurança)
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
