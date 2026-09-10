-- =============================================================================
-- 0049 · Etapa 27C — FTTH: fios com vértices (traçado real dos cabos)
-- =============================================================================
-- O fio POP→CTO e o fio CTO→cliente deixam de ser linha reta: guardam uma
-- rota de vértices [[lat,lng],...] desenhada clicando no mapa (postes/esquinas).
-- ctos.rota_pop: vértices intermediários entre o POP e a CTO.
-- cto_portas.rota_cliente: vértices a partir da CTO; o ÚLTIMO ponto é o local
-- do cliente (cliente_latitude/longitude são preenchidos a partir dele).
-- =============================================================================

alter table public.ctos add column rota_pop jsonb;
alter table public.cto_portas add column rota_cliente jsonb;

create or replace function public.validar_rota(p_rota jsonb)
returns void
language plpgsql
immutable
set search_path = public
as $$
declare v jsonb;
begin
  if p_rota is null then return; end if;
  if jsonb_typeof(p_rota) <> 'array' or jsonb_array_length(p_rota) > 200 then
    raise exception 'Rota inválida: lista de até 200 pontos [lat,lng].' using errcode = 'check_violation';
  end if;
  for v in select * from jsonb_array_elements(p_rota) loop
    if jsonb_typeof(v) <> 'array' or jsonb_array_length(v) <> 2
       or jsonb_typeof(v->0) <> 'number' or jsonb_typeof(v->1) <> 'number'
       or (v->>0)::numeric not between -90 and 90 or (v->>1)::numeric not between -180 and 180 then
      raise exception 'Rota inválida: cada ponto deve ser [latitude, longitude].' using errcode = 'check_violation';
    end if;
  end loop;
end;
$$;
revoke all on function public.validar_rota(jsonb) from public, anon, authenticated;

-- fio POP→CTO (vértices intermediários; vazio/null = linha reta)
create function public.rota_pop_cto(p_cto_id uuid, p_rota jsonb)
returns public.ctos
language plpgsql
security definer
set search_path = public
as $$
declare c public.ctos%rowtype;
begin
  select * into c from public.ctos where id = p_cto_id;
  if not found then raise exception 'CTO não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(c.organizacao_id);
  if c.tipo <> 'cto' or c.pop_id is null then
    raise exception 'Defina primeiro de qual POP vem a fibra desta CTO.' using errcode = 'check_violation';
  end if;
  perform public.validar_rota(p_rota);
  update public.ctos set rota_pop = nullif(p_rota, '[]'::jsonb) where id = p_cto_id returning * into c;
  return c;
end;
$$;
revoke all on function public.rota_pop_cto(uuid, jsonb) from public, anon;
grant execute on function public.rota_pop_cto(uuid, jsonb) to authenticated;

-- fio CTO→cliente: o último ponto da rota é o local do cliente
create or replace function public.local_cliente_porta(p_porta_id uuid, p_latitude numeric, p_longitude numeric)
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
  update public.cto_portas
     set cliente_latitude = p_latitude, cliente_longitude = p_longitude,
         rota_cliente = jsonb_build_array(jsonb_build_array(p_latitude, p_longitude))
   where id = p_porta_id returning * into pt;
  return pt;
end;
$$;

create function public.rota_cliente_porta(p_porta_id uuid, p_rota jsonb)
returns public.cto_portas
language plpgsql
security definer
set search_path = public
as $$
declare pt public.cto_portas%rowtype; ult jsonb;
begin
  select * into pt from public.cto_portas where id = p_porta_id;
  if not found then raise exception 'Porta não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(pt.organizacao_id);
  if pt.status = 'livre' then raise exception 'Desenhe o fio só em porta com cliente.' using errcode = 'check_violation'; end if;
  perform public.validar_rota(p_rota);
  if p_rota is null or jsonb_array_length(p_rota) = 0 then
    raise exception 'A rota precisa de pelo menos 1 ponto (o local do cliente).' using errcode = 'check_violation';
  end if;
  ult := p_rota -> (jsonb_array_length(p_rota) - 1);
  perform set_config('erp.motor', 'on', true);
  update public.cto_portas
     set rota_cliente = p_rota,
         cliente_latitude = (ult->>0)::numeric, cliente_longitude = (ult->>1)::numeric
   where id = p_porta_id returning * into pt;
  return pt;
end;
$$;
revoke all on function public.rota_cliente_porta(uuid, jsonb) from public, anon;
grant execute on function public.rota_cliente_porta(uuid, jsonb) to authenticated;

-- view recriada com as colunas novas
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
