-- Etapa 61 — CRM / Gestão de leads (captura, funil, conversão, dashboard). Escopo aprovado
-- pelo proprietário: sem drag-and-drop (botão "mover etapa" resolve igual), sem follow-up
-- automático nem captura via WhatsApp inbound (ficam pra etapa 62 — são peças tecnicamente
-- novas: webhook recebendo mensagem, robô que manda mensagem sozinho).
--
-- Decisões de arquitetura (aprovadas):
-- - 2 tabelas, não 3: lead_historico (mudança de status) reaproveita a auditoria genérica
--   (tg_auditoria, já usada em outras tabelas) em vez de tabela própria — menos código, mesma
--   informação. lead_eventos fica só pra interação manual (ligação/whatsapp/email/visita).
-- - Lead com campos mínimos, nunca duplica Pessoas: sem CPF/documento.
-- - Conversão não cria contrato sozinha: só pessoa + vínculo cliente. O app pré-preenche o
--   formulário de Novo contrato (pessoa/plano) pra revisão manual — contrato precisa de conta,
--   dia de vencimento etc. que o lead não tem, e um contrato errado criado sozinho é pior do
--   que nenhum.

create type public.status_lead as enum ('novo', 'contatado', 'qualificado', 'negociando', 'fechado', 'perdido');
create type public.origem_lead as enum ('site', 'whatsapp', 'indicacao', 'manual', 'api');
create type public.tipo_interacao_lead as enum ('ligacao', 'whatsapp', 'email', 'visita');

create table public.leads (
  id                   uuid primary key default gen_random_uuid(),
  organizacao_id       uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id           uuid not null references public.negocios (id) on delete restrict,
  nome                 text not null check (char_length(btrim(nome)) between 2 and 120),
  telefone             text not null check (telefone ~ '^[0-9]{10,13}$'),
  email                text check (email is null or (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 120)),
  endereco             text check (endereco is null or char_length(endereco) <= 200),
  origem               public.origem_lead not null default 'manual',
  plano_interesse_id   uuid references public.planos (id),
  status               public.status_lead not null default 'novo',
  observacao           text check (observacao is null or char_length(observacao) <= 500),
  convertido_pessoa_id uuid references public.pessoas (id),
  convertido_em        timestamptz,
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now()
);
create index leads_organizacao_status_idx on public.leads (organizacao_id, status);
create index leads_negocio_idx on public.leads (negocio_id);
comment on table public.leads is 'CRM: lead captado até virar cliente. Campos mínimos de propósito — não duplica Pessoas (sem CPF/documento). convertido_pessoa_id linka quem ele virou.';

create table public.lead_eventos (
  id         uuid primary key default gen_random_uuid(),
  lead_id    uuid not null references public.leads (id) on delete cascade,
  tipo       public.tipo_interacao_lead not null,
  descricao  text check (descricao is null or char_length(descricao) <= 500),
  usuario_id uuid references auth.users (id),
  criado_em  timestamptz not null default now()
);
create index lead_eventos_lead_idx on public.lead_eventos (lead_id, criado_em desc);
comment on table public.lead_eventos is 'Interação manual com o lead (ligação/whatsapp/email/visita) — imutável, é histórico. Mudança de status já fica em auditoria (tg_auditoria), não duplica aqui.';

-- -----------------------------------------------------------------------------
-- Normalização e proteção
-- -----------------------------------------------------------------------------
create function public.tg_leads_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.nome := btrim(new.nome);
  new.telefone := regexp_replace(coalesce(new.telefone, ''), '[^0-9]', '', 'g');
  new.email := nullif(lower(btrim(coalesce(new.email, ''))), '');
  if new.plano_interesse_id is not null
     and not exists (select 1 from public.planos where id = new.plano_interesse_id and negocio_id = new.negocio_id) then
    raise exception 'O plano de interesse não pertence a este negócio.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.tg_leads_protecao() from public, anon, authenticated;

create trigger leads_protecao before insert or update on public.leads for each row execute function public.tg_leads_protecao();
create trigger leads_atualizado before update on public.leads for each row execute function public.tg_atualizado_em();
create trigger leads_auditoria after insert or update or delete on public.leads for each row execute function public.tg_auditoria();

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.leads enable row level security;
alter table public.lead_eventos enable row level security;

create policy leads_org on public.leads
  using (organizacao_id in (select public.minhas_organizacoes()))
  with check (organizacao_id in (select public.minhas_organizacoes()));

create policy lead_eventos_org on public.lead_eventos
  using (exists (select 1 from public.leads l where l.id = lead_id and l.organizacao_id in (select public.minhas_organizacoes())))
  with check (exists (select 1 from public.leads l where l.id = lead_id and l.organizacao_id in (select public.minhas_organizacoes())));

revoke all on public.leads, public.lead_eventos from public, anon, authenticated;
grant select, insert, update on public.leads to authenticated;
grant select, insert on public.lead_eventos to authenticated; -- imutável: sem update/delete, é histórico

-- -----------------------------------------------------------------------------
-- Conversão: cria pessoa + vínculo cliente, linka o lead. NÃO cria contrato — o app
-- pré-preenche o formulário de Novo contrato com o que esta função devolve.
-- -----------------------------------------------------------------------------
create function public.converter_lead_pessoa(p_lead_id uuid)
returns public.pessoas
language plpgsql
security definer
set search_path = public
as $$
declare l public.leads%rowtype; p public.pessoas%rowtype;
begin
  select * into l from public.leads where id = p_lead_id;
  if not found then raise exception 'Lead não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.convertido_pessoa_id is not null then
    raise exception 'Este lead já foi convertido em cliente.' using errcode = 'check_violation';
  end if;

  insert into public.pessoas (organizacao_id, tipo, nome, email, telefone, endereco)
  values (l.organizacao_id, 'fisica', l.nome, l.email, l.telefone, l.endereco)
  returning * into p;

  insert into public.pessoa_negocio_vinculos (organizacao_id, pessoa_id, negocio_id, papel)
  values (l.organizacao_id, p.id, l.negocio_id, 'cliente');

  update public.leads set convertido_pessoa_id = p.id, convertido_em = now(), status = 'fechado' where id = l.id;

  return p;
end;
$$;
revoke all on function public.converter_lead_pessoa(uuid) from public, anon;
grant execute on function public.converter_lead_pessoa(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Captura pública (formulário no site, sem login) — origem fixa 'site'. Mesmo padrão de
-- portal_indicacao_publica/vitrine_publica: security definer, só o essencial exposto.
-- -----------------------------------------------------------------------------
create function public.lead_publico_capturar(p_slug text, p_nome text, p_telefone text, p_email text default null, p_plano_interesse_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_neg public.negocios%rowtype; v_tel text;
begin
  select * into v_neg from public.negocios where slug = lower(btrim(coalesce(p_slug, ''))) and ativo;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;

  if p_nome is null or char_length(btrim(p_nome)) < 2 then
    raise exception 'Nome inválido.' using errcode = 'check_violation';
  end if;
  v_tel := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  if char_length(v_tel) < 10 or char_length(v_tel) > 13 then
    raise exception 'Telefone inválido.' using errcode = 'check_violation';
  end if;
  if p_plano_interesse_id is not null
     and not exists (select 1 from public.planos where id = p_plano_interesse_id and negocio_id = v_neg.id and ativo) then
    raise exception 'Plano inválido.' using errcode = 'check_violation';
  end if;

  insert into public.leads (organizacao_id, negocio_id, nome, telefone, email, origem, plano_interesse_id)
  values (v_neg.organizacao_id, v_neg.id, btrim(p_nome), v_tel, nullif(lower(btrim(coalesce(p_email, ''))), ''), 'site', p_plano_interesse_id);

  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.lead_publico_capturar(text, text, text, text, uuid) from public;
grant execute on function public.lead_publico_capturar(text, text, text, text, uuid) to anon;
