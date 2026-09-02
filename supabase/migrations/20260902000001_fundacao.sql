-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0001: FUNDAÇÃO
-- Escopo: organizacoes, membros, auditoria, RLS, criação automática no signup.
-- Nenhuma tabela financeira é criada aqui (Etapas 3+).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tabelas
-- -----------------------------------------------------------------------------

-- Organização = escopo raiz dos dados (a holding). Chave de escopo de todo o sistema.
create table public.organizacoes (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null check (char_length(btrim(nome)) between 1 and 120),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
comment on table public.organizacoes is 'Escopo raiz: cada registro financeiro pertence a exatamente uma organização.';

create type public.papel_membro as enum ('proprietario', 'membro');

create table public.organizacao_membros (
  organizacao_id uuid not null references public.organizacoes (id) on delete cascade,
  usuario_id  uuid not null references auth.users (id) on delete cascade,
  papel       public.papel_membro not null default 'membro',
  criado_em   timestamptz not null default now(),
  primary key (organizacao_id, usuario_id)
);
create index organizacao_membros_usuario_idx on public.organizacao_membros (usuario_id);
comment on table public.organizacao_membros is 'Vínculo usuário (auth.users) × organização, com papel.';

-- Auditoria: trilha imutável. Sem FK para organizacoes de propósito: o histórico
-- precisa sobreviver a qualquer remoção futura.
create table public.auditoria (
  id           bigint generated always as identity primary key,
  organizacao_id  uuid,
  tabela       text not null,
  registro_id  text not null,
  acao         text not null check (acao in ('INSERT', 'UPDATE', 'DELETE')),
  dados_antes  jsonb,
  dados_depois jsonb,
  usuario_id   uuid,
  quando       timestamptz not null default now()
);
create index auditoria_organizacao_idx on public.auditoria (organizacao_id, quando desc);
create index auditoria_registro_idx on public.auditoria (tabela, registro_id);
comment on table public.auditoria is 'Trilha de auditoria preenchida exclusivamente por trigger. Somente leitura para clientes.';

-- -----------------------------------------------------------------------------
-- 2. Funções de infraestrutura
-- -----------------------------------------------------------------------------

-- Mantém atualizado_em.
create or replace function public.tg_atualizado_em()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

-- Trigger genérico de auditoria. SECURITY DEFINER porque auditoria não possui
-- policy de escrita: só este caminho consegue gravar nela.
create or replace function public.tg_auditoria()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes  jsonb;
  v_depois jsonb;
  v_ref    jsonb;
  v_ent    uuid;
begin
  if tg_op <> 'INSERT' then v_antes  := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_depois := to_jsonb(new); end if;
  v_ref := coalesce(v_depois, v_antes);

  v_ent := case
    when tg_table_name = 'organizacoes' then (v_ref ->> 'id')::uuid
    else (v_ref ->> 'organizacao_id')::uuid
  end;

  insert into public.auditoria (organizacao_id, tabela, registro_id, acao, dados_antes, dados_depois, usuario_id)
  values (
    v_ent,
    tg_table_name,
    coalesce(v_ref ->> 'id', concat_ws(':', v_ref ->> 'organizacao_id', v_ref ->> 'usuario_id')),
    tg_op,
    v_antes,
    v_depois,
    auth.uid()
  );

  return coalesce(new, old);
end;
$$;

-- Organizacoes às quais o usuário autenticado pertence. SECURITY DEFINER para que
-- as policies possam consultá-la sem recursão de RLS.
create or replace function public.minhas_organizacoes()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select organizacao_id from public.organizacao_membros where usuario_id = auth.uid();
$$;

create or replace function public.sou_proprietario(p_organizacao uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.organizacao_membros
    where organizacao_id = p_organizacao and usuario_id = auth.uid() and papel = 'proprietario'
  );
$$;

-- Ao criar usuário no Auth, cria a organização dele e o torna proprietário.
create or replace function public.tg_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_nome text;
begin
  v_nome := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'nome'), ''),
    split_part(coalesce(new.email, ''), '@', 1),
    'Minha organizacao'
  );
  if char_length(v_nome) = 0 then v_nome := 'Minha organizacao'; end if;

  insert into public.organizacoes (nome) values (left(v_nome, 120)) returning id into v_id;
  insert into public.organizacao_membros (organizacao_id, usuario_id, papel)
  values (v_id, new.id, 'proprietario');

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. Triggers
-- -----------------------------------------------------------------------------
create trigger organizacoes_atualizado_em
  before update on public.organizacoes
  for each row execute function public.tg_atualizado_em();

create trigger organizacoes_auditoria
  after insert or update or delete on public.organizacoes
  for each row execute function public.tg_auditoria();

create trigger organizacao_membros_auditoria
  after insert or update or delete on public.organizacao_membros
  for each row execute function public.tg_auditoria();

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.tg_novo_usuario();

-- -----------------------------------------------------------------------------
-- 4. Privilégios (defesa em profundidade, além do RLS)
-- -----------------------------------------------------------------------------
revoke all on public.organizacoes        from anon, authenticated;
revoke all on public.organizacao_membros from anon, authenticated;
revoke all on public.auditoria        from anon, authenticated;

grant select, update on public.organizacoes        to authenticated;
grant select         on public.organizacao_membros to authenticated;
grant select         on public.auditoria        to authenticated;

revoke all on function public.tg_atualizado_em()   from public, anon, authenticated;
revoke all on function public.tg_auditoria()       from public, anon, authenticated;
revoke all on function public.tg_novo_usuario()    from public, anon, authenticated;
revoke all on function public.minhas_organizacoes()   from public, anon;
revoke all on function public.sou_proprietario(uuid) from public, anon;
grant execute on function public.minhas_organizacoes()     to authenticated;
grant execute on function public.sou_proprietario(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. RLS
-- -----------------------------------------------------------------------------
alter table public.organizacoes        enable row level security;
alter table public.organizacao_membros enable row level security;
alter table public.auditoria        enable row level security;

-- organizacoes: membro lê; proprietário edita. Sem insert/delete via cliente
-- (criação só pelo trigger de signup; exclusão não existe nesta etapa).
create policy organizacoes_select on public.organizacoes
  for select to authenticated
  using (id in (select public.minhas_organizacoes()));

create policy organizacoes_update on public.organizacoes
  for update to authenticated
  using (public.sou_proprietario(id))
  with check (public.sou_proprietario(id));

-- organizacao_membros: membro vê os membros da sua organização. Sem escrita via cliente.
create policy organizacao_membros_select on public.organizacao_membros
  for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));

-- auditoria: membro lê a trilha da sua organização. Sem escrita via cliente.
create policy auditoria_select on public.auditoria
  for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));
