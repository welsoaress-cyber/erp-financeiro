-- =============================================================================
-- 0059 · Etapa 31 — Pix automático (Mercado Pago) + bloqueio assistido
-- =============================================================================
-- Pix: o cliente paga a fatura pelo portal com Pix copia-e-cola gerado no
-- Mercado Pago (taxa por transação autorizada pelo proprietário). O token fica
-- SÓ nos secrets das Edge Functions (pix-gerar, pix-webhook) — nada no banco
-- nem no repositório. O webhook confirma o pagamento consultando a API do MP
-- (fonte da verdade) e baixa o lançamento na conta Pix configurada do negócio.
-- O aviso de cobrança do WhatsApp passa a poder anexar o copia-e-cola (a Edge
-- notificacoes-enviar gera/reaproveita a cobrança quando o Pix está ativo).
-- Bloqueio assistido: o sistema monta a lista de quem bloquear (cobrança
-- vencida além do prazo da régua) e desbloquear (suspenso sem vencidas);
-- o admin executa na rede e marca. Executar muda o status do contrato
-- (ativo↔suspenso). Nada de corte automático.
-- =============================================================================

-- Baixa interna do Pix: espelho EXATO de efetivar_lancamento (0041) sem a
-- checagem de membro — o webhook roda como service_role, sem usuário logado.
-- Privada: revogada de todos; só pix_confirmar (grant service_role) a chama.
-- Se efetivar_lancamento mudar em migration futura, atualizar este espelho.
create function public.pix_efetivar_interno(p_id uuid, p_data_efetivacao date default current_date, p_encargos numeric default 0, p_conta_id uuid default null)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  n public.lancamentos%rowtype;
  v_valor_original numeric;
  v_obs_original text;
  v_conta_original uuid;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  -- sem checagem de membro: privada, chamada apenas por pix_confirmar (service_role)
  if l.status <> 'previsto' then
    raise exception 'Somente lançamentos previstos podem ser efetivados.' using errcode = 'check_violation';
  end if;
  if p_encargos is null or p_encargos < 0 then
    raise exception 'Encargos não podem ser negativos.' using errcode = 'check_violation';
  end if;
  if p_conta_id is not null and p_conta_id <> l.conta_id then
    if l.tipo = 'transferencia' then
      raise exception 'Transferência não muda de conta na baixa.' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from public.contas c where c.id = p_conta_id and c.organizacao_id = l.organizacao_id) then
      raise exception 'Conta inválida para esta organização.' using errcode = 'check_violation';
    end if;
  end if;
  perform set_config('erp.motor', 'on', true);
  v_valor_original := l.valor;
  v_obs_original := l.observacao;
  v_conta_original := l.conta_id;
  if p_conta_id is not null and p_conta_id <> l.conta_id then
    perform set_config('erp.trocar_conta', 'on', true);
    update public.lancamentos set conta_id = p_conta_id where id = p_id;
  end if;
  if p_encargos > 0 then
    update public.lancamentos
       set valor = valor + round(p_encargos, 2),
           observacao = trim(both e'\n' from coalesce(observacao, '') || e'\n' ||
             'Encargos por atraso: R$ ' || replace(to_char(round(p_encargos, 2), 'FM999999990.00'), '.', ','))
     where id = p_id;
  end if;
  update public.lancamentos set status = 'efetivado', data_efetivacao = p_data_efetivacao where id = p_id returning * into l;
  perform public.gerar_movimentos(l.id);
  n := public.gerar_proxima_parcela(l.id);
  -- encargos e troca de conta são só desta parcela: a próxima (quando gerada aqui) volta ao original
  if n.id is not null then
    update public.lancamentos
       set valor = case when p_encargos > 0 then v_valor_original else valor end,
           observacao = case when p_encargos > 0 then v_obs_original else observacao end,
           conta_id = v_conta_original
     where id = n.id;
  end if;
  if p_data_efetivacao > l.data_vencimento then
    if l.recorrente then
      perform public.reancorar_recorrencia(l.id, p_data_efetivacao);
    elsif l.contrato_id is not null and l.origem = 'faturamento' then
      update public.contratos
         set dia_vencimento = least(extract(day from p_data_efetivacao)::int, 31)::smallint
       where id = l.contrato_id and status = 'ativo';
    end if;
  end if;
  return l;
end;
$$;
revoke all on function public.pix_efetivar_interno(uuid, date, numeric, uuid) from public, anon, authenticated;

alter table public.portal_config add column pix_automatico boolean not null default false;
alter table public.portal_config add column conta_pix_id uuid references public.contas (id);

create type public.status_pix as enum ('pendente', 'pago', 'expirado', 'cancelado', 'erro');

create table public.pix_cobrancas (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  lancamento_id uuid not null references public.lancamentos (id),
  pessoa_id uuid references public.pessoas (id),
  txid text not null unique,
  valor numeric(14,2) not null check (valor > 0),
  copia_cola text not null,
  ticket_url text,
  status public.status_pix not null default 'pendente',
  expira_em timestamptz,
  pago_em timestamptz,
  resposta jsonb,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index pix_cobrancas_lancamento on public.pix_cobrancas (lancamento_id);
create unique index pix_cobrancas_pendente_unica on public.pix_cobrancas (lancamento_id) where status = 'pendente';
create trigger pix_cobrancas_atualizado before update on public.pix_cobrancas for each row execute function public.tg_atualizado_em();
create trigger pix_cobrancas_auditoria after insert or update or delete on public.pix_cobrancas for each row execute function public.tg_auditoria();

alter table public.pix_cobrancas enable row level security;
create policy pix_cobrancas_org on public.pix_cobrancas for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.pix_cobrancas from public, anon, authenticated;
grant select on public.pix_cobrancas to authenticated;

-- -----------------------------------------------------------------------------
-- Fila e registro (service_role — Edge Functions)
-- -----------------------------------------------------------------------------
-- Dados para a Edge gerar a cobrança de um lançamento (valida vínculo e config)
create function public.pix_dados_lancamento(p_lancamento_id uuid)
returns table (lancamento_id uuid, organizacao_id uuid, negocio_id uuid, pessoa_id uuid, valor numeric,
               descricao text, vencimento date, cliente text, documento text, email text,
               pix_automatico boolean, cobranca_pendente text)
language sql
stable
security definer
set search_path = public
as $$
  select l.id, l.organizacao_id, c.negocio_id, l.pessoa_id, l.valor, l.descricao, l.data_vencimento,
         pe.nome, pe.documento, pe.email, coalesce(pc.pix_automatico, false),
         (select px.copia_cola from public.pix_cobrancas px
           where px.lancamento_id = l.id and px.status = 'pendente' and (px.expira_em is null or px.expira_em > now() + interval '1 hour') limit 1)
    from public.lancamentos l
    join public.contratos c on c.id = l.contrato_id
    left join public.pessoas pe on pe.id = l.pessoa_id
    left join public.portal_config pc on pc.negocio_id = c.negocio_id
   where l.id = p_lancamento_id and l.tipo = 'receita' and l.status = 'previsto';
$$;

create function public.pix_registrar(p_lancamento_id uuid, p_txid text, p_copia_cola text, p_ticket_url text, p_expira_em timestamptz, p_resposta jsonb default null)
returns public.pix_cobrancas
language plpgsql
security definer
set search_path = public
as $$
declare l public.lancamentos%rowtype; v_neg uuid; px public.pix_cobrancas%rowtype;
begin
  select * into l from public.lancamentos where id = p_lancamento_id;
  if l.id is null or l.tipo <> 'receita' or l.status <> 'previsto' then
    raise exception 'Lançamento inválido para cobrança Pix.' using errcode = 'check_violation';
  end if;
  select negocio_id into v_neg from public.contratos where id = l.contrato_id;
  update public.pix_cobrancas set status = 'cancelado' where lancamento_id = p_lancamento_id and status = 'pendente';
  insert into public.pix_cobrancas (organizacao_id, negocio_id, lancamento_id, pessoa_id, txid, valor, copia_cola, ticket_url, status, expira_em, resposta)
  values (l.organizacao_id, coalesce(v_neg, l.negocio_id), p_lancamento_id, l.pessoa_id, p_txid, l.valor, p_copia_cola, p_ticket_url, 'pendente', p_expira_em, p_resposta)
  returning * into px;
  return px;
end;
$$;

-- Confirmação (webhook): marca pago e baixa o lançamento na conta Pix do negócio
create function public.pix_confirmar(p_txid text, p_valor_pago numeric default null, p_resposta jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare px public.pix_cobrancas%rowtype; l public.lancamentos%rowtype; v_conta uuid;
begin
  select * into px from public.pix_cobrancas where txid = p_txid;
  if px.id is null then return jsonb_build_object('ok', false, 'motivo', 'txid desconhecido'); end if;
  if px.status = 'pago' then return jsonb_build_object('ok', true, 'motivo', 'já confirmado'); end if;
  select * into l from public.lancamentos where id = px.lancamento_id;
  update public.pix_cobrancas set status = 'pago', pago_em = now(), resposta = coalesce(p_resposta, resposta) where id = px.id;
  if l.status = 'previsto' then
    select conta_pix_id into v_conta from public.portal_config where negocio_id = px.negocio_id;
    perform public.pix_efetivar_interno(px.lancamento_id, current_date, 0, coalesce(v_conta, l.conta_id));
  end if;
  return jsonb_build_object('ok', true, 'lancamento_id', px.lancamento_id, 'valor', px.valor, 'valor_pago', p_valor_pago);
end;
$$;

create function public.pix_marcar_erro(p_txid text, p_status text, p_resposta jsonb default null)
returns void
language sql
security definer
set search_path = public
as $$
  update public.pix_cobrancas set status = p_status::public.status_pix, resposta = coalesce(p_resposta, resposta)
   where txid = p_txid and status = 'pendente';
$$;

revoke all on function public.pix_dados_lancamento(uuid), public.pix_registrar(uuid, text, text, text, timestamptz, jsonb),
  public.pix_confirmar(text, numeric, jsonb), public.pix_marcar_erro(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.pix_dados_lancamento(uuid), public.pix_registrar(uuid, text, text, text, timestamptz, jsonb),
  public.pix_confirmar(text, numeric, jsonb), public.pix_marcar_erro(text, text, jsonb) to service_role;

-- Portal: cobrança pendente do próprio cliente (para reexibir o copia-e-cola)
create function public.portal_pix_cobranca(p_lancamento_id uuid)
returns table (copia_cola text, ticket_url text, expira_em timestamptz, status public.status_pix)
language sql
stable
security definer
set search_path = public
as $$
  select px.copia_cola, px.ticket_url, px.expira_em, px.status
    from public.pix_cobrancas px
    join public.lancamentos l on l.id = px.lancamento_id
   where px.lancamento_id = p_lancamento_id and l.pessoa_id = public.portal_pessoa()
   order by px.criado_em desc limit 1;
$$;
revoke all on function public.portal_pix_cobranca(uuid) from public, anon;
grant execute on function public.portal_pix_cobranca(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Bloqueio assistido
-- -----------------------------------------------------------------------------
create type public.tipo_bloqueio as enum ('bloqueio', 'desbloqueio');
create type public.status_bloqueio as enum ('pendente', 'executado', 'descartado');

create table public.bloqueios (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  contrato_id uuid not null references public.contratos (id),
  pessoa_id uuid not null references public.pessoas (id),
  tipo public.tipo_bloqueio not null,
  status public.status_bloqueio not null default 'pendente',
  motivo text not null,
  criado_em timestamptz not null default now(),
  executado_em timestamptz,
  usuario_id uuid
);
create unique index bloqueios_pendente_unico on public.bloqueios (contrato_id, tipo) where status = 'pendente';
create index bloqueios_negocio on public.bloqueios (negocio_id, status);
create trigger bloqueios_auditoria after insert or update or delete on public.bloqueios for each row execute function public.tg_auditoria();

alter table public.bloqueios enable row level security;
create policy bloqueios_org on public.bloqueios for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.bloqueios from public, anon, authenticated;
grant select on public.bloqueios to authenticated;

-- Monta a lista: bloqueio para contrato ativo com cobrança vencida além do prazo da régua
-- (dias_apos da config de notificações; sem config, 3 dias); desbloqueio para suspenso sem vencidas.
create function public.gerar_bloqueios(p_negocio_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; v_dias int; v_blq int := 0; v_dsb int := 0; r record;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(n.organizacao_id);
  select coalesce(max(dias_apos), 3) into v_dias from public.notificacoes_config where negocio_id = p_negocio_id;

  for r in
    select c.id, c.pessoa_id, min(l.data_vencimento) as vencida_desde, count(l.id) as vencidas, sum(l.valor) as total
      from public.contratos c
      join public.lancamentos l on l.contrato_id = c.id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date - v_dias
     where c.negocio_id = p_negocio_id and c.status = 'ativo' and c.tipo_financeiro = 'receita'
     group by c.id, c.pessoa_id
  loop
    insert into public.bloqueios (organizacao_id, negocio_id, contrato_id, pessoa_id, tipo, motivo)
    values (n.organizacao_id, p_negocio_id, r.id, r.pessoa_id, 'bloqueio',
            r.vencidas || ' cobrança(s) vencida(s) desde ' || to_char(r.vencida_desde, 'DD/MM/YYYY') || ' · R$ ' || to_char(r.total, 'FM999G999G990D00'))
    on conflict do nothing;
    v_blq := v_blq + 1;
  end loop;

  for r in
    select c.id, c.pessoa_id
      from public.contratos c
     where c.negocio_id = p_negocio_id and c.status = 'suspenso' and c.tipo_financeiro = 'receita'
       and not exists (select 1 from public.lancamentos l where l.contrato_id = c.id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date)
  loop
    insert into public.bloqueios (organizacao_id, negocio_id, contrato_id, pessoa_id, tipo, motivo)
    values (n.organizacao_id, p_negocio_id, r.id, r.pessoa_id, 'desbloqueio', 'Pagamentos em dia — liberar o acesso')
    on conflict do nothing;
    v_dsb := v_dsb + 1;
  end loop;

  -- pendências que deixaram de valer somem sozinhas
  update public.bloqueios b set status = 'descartado'
   where b.negocio_id = p_negocio_id and b.status = 'pendente' and b.tipo = 'bloqueio'
     and not exists (select 1 from public.lancamentos l where l.contrato_id = b.contrato_id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date - v_dias);
  update public.bloqueios b set status = 'descartado'
   where b.negocio_id = p_negocio_id and b.status = 'pendente' and b.tipo = 'desbloqueio'
     and not exists (select 1 from public.contratos c where c.id = b.contrato_id and c.status = 'suspenso');

  return jsonb_build_object('bloqueios', v_blq, 'desbloqueios', v_dsb);
end;
$$;

-- Admin executou na rede: marca e muda o status do contrato (ativo↔suspenso)
create function public.executar_bloqueio(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare b public.bloqueios%rowtype;
begin
  select * into b from public.bloqueios where id = p_id;
  if not found then raise exception 'Item não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(b.organizacao_id);
  if b.status <> 'pendente' then raise exception 'Item já tratado.' using errcode = 'check_violation'; end if;
  update public.bloqueios set status = 'executado', executado_em = now(), usuario_id = auth.uid() where id = p_id;
  update public.contratos set status = case when b.tipo = 'bloqueio' then 'suspenso' else 'ativo' end::public.status_contrato
   where id = b.contrato_id and status = case when b.tipo = 'bloqueio' then 'ativo' else 'suspenso' end::public.status_contrato;
end;
$$;

create function public.descartar_bloqueio(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare b public.bloqueios%rowtype;
begin
  select * into b from public.bloqueios where id = p_id;
  if not found then raise exception 'Item não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(b.organizacao_id);
  if b.status <> 'pendente' then raise exception 'Item já tratado.' using errcode = 'check_violation'; end if;
  update public.bloqueios set status = 'descartado', executado_em = now(), usuario_id = auth.uid() where id = p_id;
end;
$$;

revoke all on function public.gerar_bloqueios(uuid), public.executar_bloqueio(uuid), public.descartar_bloqueio(uuid) from public, anon;
grant execute on function public.gerar_bloqueios(uuid), public.executar_bloqueio(uuid), public.descartar_bloqueio(uuid) to authenticated;
