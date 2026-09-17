create extension if not exists pgcrypto; -- no Supabase hospedado já vem instalado no schema "extensions" (por isso o
-- search_path das funções abaixo inclui "extensions"); aqui é só garantia pra quem reaplicar do zero num banco novo.

-- Etapa 56: API de consulta de cliente por CPF/CNPJ, para integrações externas
-- (hoje: Leveduca — clube de benefícios revendido junto do plano de internet).
-- O token nunca é gravado em texto puro: só o hash (sha256) fica no banco; o
-- valor real é mostrado uma única vez, na hora de gerar, e o app não tem como
-- recuperá-lo depois — só revogar e gerar outro. A consulta em si roda na Edge
-- Function `api-consulta-cliente` com a service role (bypassa RLS de propósito:
-- quem chama não tem sessão nossa, só o token); aqui só ficam a tabela do token,
-- o log de auditoria e as funções para o admin gerenciar pelo app.
create table public.api_tokens (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  nome           text not null check (char_length(btrim(nome)) between 2 and 60),
  token_hash     text not null unique,
  token_prefixo  text not null, -- 8 primeiros caracteres do token, só para o admin reconhecer qual é qual na lista
  ativo          boolean not null default true,
  criado_por     uuid,
  criado_em      timestamptz not null default now(),
  revogado_em    timestamptz,
  ultimo_uso_em  timestamptz,
  check ((ativo = false) = (revogado_em is not null))
);
create index api_tokens_organizacao_idx on public.api_tokens (organizacao_id);
comment on table public.api_tokens is 'Tokens de integrações externas (ex.: Leveduca) que consultam dados de cliente pela Edge Function api-consulta-cliente. Só o hash é gravado.';

create table public.api_consultas (
  id                    uuid primary key default gen_random_uuid(),
  organizacao_id        uuid not null references public.organizacoes (id) on delete restrict,
  token_id              uuid not null references public.api_tokens (id) on delete restrict,
  documento_consultado  text not null,
  encontrado            boolean not null,
  criado_em             timestamptz not null default now()
);
create index api_consultas_organizacao_idx on public.api_consultas (organizacao_id, criado_em desc);
comment on table public.api_consultas is 'Auditoria: cada chamada à api-consulta-cliente, quem (token) consultou o quê e se achou.';

alter table public.api_tokens enable row level security;
alter table public.api_consultas enable row level security;
create policy api_tokens_org on public.api_tokens for select using (organizacao_id in (select public.minhas_organizacoes()));
create policy api_consultas_org on public.api_consultas for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.api_tokens, public.api_consultas from public, anon, authenticated;
grant select on public.api_tokens, public.api_consultas to authenticated;

create view public.vw_api_tokens with (security_invoker = true) as
select t.id, t.organizacao_id, t.negocio_id, n.nome as negocio, t.nome, t.token_prefixo, t.ativo,
       t.criado_em, t.revogado_em, t.ultimo_uso_em,
       coalesce(u.consultas, 0) as consultas
  from public.api_tokens t
  join public.negocios n on n.id = t.negocio_id
  left join lateral (select count(*) as consultas from public.api_consultas c where c.token_id = t.id) u on true;
grant select on public.vw_api_tokens to authenticated;

-- Relatório: quem consultou o quê (Central de Relatórios) — sem CPF completo, só os 3 últimos dígitos.
create view public.vw_rel_api_consultas with (security_invoker = true) as
select c.id, c.organizacao_id, t.negocio_id, n.nome as negocio, t.nome as token,
       (case when c.encontrado then 'Encontrado' else 'Não encontrado' end) as situacao,
       ('***' || right(c.documento_consultado, 3)) as documento_mascarado, c.criado_em
  from public.api_consultas c
  join public.api_tokens t on t.id = c.token_id
  join public.negocios n on n.id = t.negocio_id;
grant select on public.vw_rel_api_consultas to authenticated;

-- Gera um token novo: devolve o valor em texto puro (única vez) + o registro criado.
-- Coluna de saída é "token_id" (não "id") de propósito: um OUT parâmetro chamado
-- "id" sombreia qualquer coluna "id" nas consultas do corpo da função inteira
-- (plpgsql.variable_conflict = error por padrão) e vira "column reference id is
-- ambiguous" na hora de buscar o negócio.
create function public.criar_api_token(p_negocio_id uuid, p_nome text)
returns table (token_id uuid, token text, token_prefixo text)
language plpgsql
security definer
set search_path = public, extensions -- pgcrypto (gen_random_bytes/digest) mora em "extensions" no Supabase hospedado
as $$
declare
  v_org uuid; v_token text; v_hash text; v_id uuid;
begin
  select organizacao_id into v_org from public.negocios where negocios.id = p_negocio_id;
  if v_org is null then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(v_org);
  if char_length(btrim(coalesce(p_nome, ''))) < 2 then raise exception 'Informe um nome para o token (ex.: Leveduca).' using errcode = 'check_violation'; end if;

  v_token := encode(gen_random_bytes(24), 'hex'); -- 48 caracteres hex, só existe em texto puro aqui e na tela
  v_hash := encode(digest(v_token, 'sha256'), 'hex');

  insert into public.api_tokens (organizacao_id, negocio_id, nome, token_hash, token_prefixo, criado_por)
  values (v_org, p_negocio_id, btrim(p_nome), v_hash, left(v_token, 8), auth.uid())
  returning api_tokens.id into v_id;

  token_id := v_id;
  token := v_token;
  token_prefixo := left(v_token, 8);
  return next;
end;
$$;
revoke all on function public.criar_api_token(uuid, text) from public, anon;
grant execute on function public.criar_api_token(uuid, text) to authenticated;

create function public.revogar_api_token(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid;
begin
  select organizacao_id into v_org from public.api_tokens where id = p_id;
  if v_org is null then raise exception 'Token não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(v_org);
  update public.api_tokens set ativo = false, revogado_em = now() where id = p_id;
end;
$$;
revoke all on function public.revogar_api_token(uuid) from public, anon;
grant execute on function public.revogar_api_token(uuid) to authenticated;
