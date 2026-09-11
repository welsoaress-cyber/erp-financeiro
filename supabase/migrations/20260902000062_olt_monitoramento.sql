-- =============================================================================
-- 0062 · Etapa 34 — Monitoramento simples da OLT (sem NOC, sem tempo real)
-- =============================================================================
-- Um agente local (mini-PC/Raspberry na central, script em supabase/scripts/
-- olt-agente.sh) pinga a OLT de cada POP e manda o resultado para a Edge
-- Function olt-ping, autenticada por segredo próprio (OLT_PING_SECRET). O ERP
-- guarda o último estado por POP (olt_status) e o histórico de MUDANÇAS
-- (olt_eventos — só quando cai ou volta, sem poluir). Quando o estado muda,
-- a própria Edge avisa no WhatsApp do administrador (numero_whatsapp da config
-- de notificações do negócio) pela Evolution — direto, sem fila.
-- =============================================================================

create table public.olt_status (
  pop_id uuid primary key references public.ctos (id),
  organizacao_id uuid not null references public.organizacoes (id),
  online boolean not null,
  latencia_ms integer,
  ultima_verificacao timestamptz not null default now(),
  mudou_em timestamptz not null default now()
);

create table public.olt_eventos (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  pop_id uuid not null references public.ctos (id),
  online boolean not null,
  latencia_ms integer,
  criado_em timestamptz not null default now()
);
create index olt_eventos_pop on public.olt_eventos (pop_id, criado_em desc);

alter table public.olt_status enable row level security;
alter table public.olt_eventos enable row level security;
create policy olt_status_org on public.olt_status for select using (organizacao_id in (select public.minhas_organizacoes()));
create policy olt_eventos_org on public.olt_eventos for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.olt_status, public.olt_eventos from public, anon, authenticated;
grant select on public.olt_status, public.olt_eventos to authenticated;

-- Registra um ping (service_role, via Edge). Devolve se o estado MUDOU e os
-- dados para o aviso (número do admin e instância Evolution do negócio).
create function public.olt_registrar_ping(p_codigo_pop text, p_online boolean, p_latencia_ms integer default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare pop public.ctos%rowtype; anterior public.olt_status%rowtype; cfg public.notificacoes_config%rowtype; v_mudou boolean;
begin
  select * into pop from public.ctos where upper(codigo) = upper(btrim(p_codigo_pop)) and tipo::text = 'pop';
  if not found then return jsonb_build_object('ok', false, 'motivo', 'POP não encontrado: ' || p_codigo_pop); end if;
  select * into anterior from public.olt_status where pop_id = pop.id;
  v_mudou := anterior.pop_id is null or anterior.online is distinct from p_online;
  insert into public.olt_status (pop_id, organizacao_id, online, latencia_ms, ultima_verificacao, mudou_em)
  values (pop.id, pop.organizacao_id, p_online, p_latencia_ms, now(), now())
  on conflict (pop_id) do update
     set online = excluded.online, latencia_ms = excluded.latencia_ms, ultima_verificacao = now(),
         mudou_em = case when public.olt_status.online is distinct from excluded.online then now() else public.olt_status.mudou_em end;
  if v_mudou then
    insert into public.olt_eventos (organizacao_id, pop_id, online, latencia_ms) values (pop.organizacao_id, pop.id, p_online, p_latencia_ms);
  end if;
  select * into cfg from public.notificacoes_config where negocio_id = pop.negocio_id;
  return jsonb_build_object('ok', true, 'mudou', v_mudou, 'pop', pop.codigo,
                            'aviso_numero', cfg.numero_whatsapp, 'instancia', cfg.instancia,
                            'avisar', v_mudou and anterior.pop_id is not null and cfg.ativo and cfg.numero_whatsapp is not null and cfg.provedor::text = 'evolution');
end;
$$;
revoke all on function public.olt_registrar_ping(text, boolean, integer) from public, anon, authenticated;
grant execute on function public.olt_registrar_ping(text, boolean, integer) to service_role;
