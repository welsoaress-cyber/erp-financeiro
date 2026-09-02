-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0004: CATEGORIAS
-- Escopo: categorias hierárquicas (2 níveis) de receita/despesa, categorias
-- padrão por organização, proteção de integridade, RLS, auditoria.
-- =============================================================================

create type public.tipo_categoria as enum ('receita', 'despesa');

create table public.categorias (
  id               uuid primary key default gen_random_uuid(),
  organizacao_id   uuid not null references public.organizacoes (id) on delete restrict,
  nome             text not null check (char_length(btrim(nome)) between 1 and 60),
  tipo             public.tipo_categoria not null,
  categoria_pai_id uuid references public.categorias (id) on delete restrict,
  ativo            boolean not null default true,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  check (categoria_pai_id is distinct from id)
);
create index categorias_organizacao_idx on public.categorias (organizacao_id, tipo);
create index categorias_pai_idx on public.categorias (categoria_pai_id);
create unique index categorias_nome_unico_idx on public.categorias (organizacao_id, tipo, lower(btrim(nome)));
comment on table public.categorias is 'Categorias de receita/despesa em até 2 níveis (categoria → subcategoria). Nunca excluídas: inativadas.';

-- Preparada para a Etapa 5: responde false até a tabela lancamentos existir.
create or replace function public.categoria_possui_lancamentos(p_categoria uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_existe boolean := false;
begin
  if to_regclass('public.lancamentos') is null then
    return false;
  end if;
  execute 'select exists (select 1 from public.lancamentos where categoria_id = $1)' into v_existe using p_categoria;
  return v_existe;
end;
$$;

create or replace function public.tg_categorias_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_pai public.categorias%rowtype;
begin
  if tg_op = 'UPDATE' then
    if new.tipo <> old.tipo then
      raise exception 'O tipo da categoria não pode ser alterado.' using errcode = 'check_violation';
    end if;
    if new.organizacao_id <> old.organizacao_id then
      raise exception 'A categoria não pode mudar de organização.' using errcode = 'check_violation';
    end if;
    if old.ativo and not new.ativo then
      if exists (select 1 from public.categorias f where f.categoria_pai_id = old.id and f.ativo) then
        raise exception 'A categoria não pode ser inativada: possui subcategorias ativas.' using errcode = 'check_violation';
      end if;
      if public.categoria_possui_lancamentos(old.id) then
        raise exception 'A categoria não pode ser inativada: já possui lançamentos.' using errcode = 'check_violation';
      end if;
    end if;
    if new.categoria_pai_id is not null
       and exists (select 1 from public.categorias f where f.categoria_pai_id = old.id) then
      raise exception 'Uma categoria com subcategorias não pode virar subcategoria.' using errcode = 'check_violation';
    end if;
  end if;

  if new.categoria_pai_id is not null then
    select * into v_pai from public.categorias where id = new.categoria_pai_id;
    if not found or v_pai.organizacao_id <> new.organizacao_id then
      raise exception 'Categoria pai inválida.' using errcode = 'check_violation';
    end if;
    if v_pai.tipo <> new.tipo then
      raise exception 'A categoria pai deve ser do mesmo tipo (receita ou despesa).' using errcode = 'check_violation';
    end if;
    if v_pai.categoria_pai_id is not null then
      raise exception 'Uma subcategoria não pode ser pai: apenas 2 níveis são permitidos.' using errcode = 'check_violation';
    end if;
    if new.ativo and not v_pai.ativo then
      raise exception 'A categoria pai está inativa.' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

create trigger categorias_protecao
  before insert or update on public.categorias
  for each row execute function public.tg_categorias_protecao();

create trigger categorias_atualizado_em
  before update on public.categorias
  for each row execute function public.tg_atualizado_em();

create trigger categorias_auditoria
  after insert or update or delete on public.categorias
  for each row execute function public.tg_auditoria();

-- Categorias padrão de uma organização (idempotente: ignora as que já existem).
create or replace function public.criar_categorias_padrao(p_organizacao uuid)
returns void
language sql
set search_path = public
as $$
  insert into public.categorias (organizacao_id, nome, tipo)
  select p_organizacao, n, t::public.tipo_categoria
  from (values
    ('Salário', 'receita'), ('Rendimento', 'receita'), ('Investimento', 'receita'), ('Outros', 'receita'),
    ('Alimentação', 'despesa'), ('Moradia', 'despesa'), ('Transporte', 'despesa'), ('Lazer', 'despesa'),
    ('Saúde', 'despesa'), ('Educação', 'despesa'), ('Outros', 'despesa')
  ) as padrao (n, t)
  on conflict do nothing;
$$;

-- Signup passa a criar também as categorias padrão.
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
  perform public.criar_categorias_padrao(v_id);

  return new;
end;
$$;

-- Organizações já existentes recebem as categorias padrão uma única vez.
do $$
declare o record;
begin
  for o in select id from public.organizacoes loop
    perform public.criar_categorias_padrao(o.id);
  end loop;
end $$;

-- Privilégios
revoke all on public.categorias from anon, authenticated;
grant select, insert, update on public.categorias to authenticated;
revoke all on function public.categoria_possui_lancamentos(uuid) from public, anon;
grant execute on function public.categoria_possui_lancamentos(uuid) to authenticated;
revoke all on function public.tg_categorias_protecao() from public, anon, authenticated;
revoke all on function public.criar_categorias_padrao(uuid) from public, anon, authenticated;

-- RLS
alter table public.categorias enable row level security;

create policy categorias_select on public.categorias
  for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));

create policy categorias_insert on public.categorias
  for insert to authenticated
  with check (organizacao_id in (select public.minhas_organizacoes()));

create policy categorias_update on public.categorias
  for update to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()))
  with check (organizacao_id in (select public.minhas_organizacoes()));
