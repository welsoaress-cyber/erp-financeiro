-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0002: CONTAS
-- Escopo: tabela contas, proteção de integridade, RLS, auditoria.
-- Saldo NÃO é armazenado: será derivado dos movimentos (Etapa 5).
-- =============================================================================

create type public.tipo_conta as enum ('corrente', 'poupanca', 'dinheiro', 'carteira_digital', 'investimento');

create table public.contas (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  nome           text not null check (char_length(btrim(nome)) between 1 and 80),
  tipo           public.tipo_conta not null,
  saldo_inicial  numeric(14,2) not null default 0 check (saldo_inicial >= 0),
  data_inicio    date not null default current_date,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create index contas_organizacao_idx on public.contas (organizacao_id);
create unique index contas_nome_unico_idx on public.contas (organizacao_id, lower(btrim(nome)));
comment on table public.contas is 'Contas (banco, dinheiro, carteira, investimento). Saldo = saldo_inicial + Σ movimentos efetivados; nunca gravado aqui.';

-- Verifica se a conta já possui movimentos. A tabela movimentos nasce na Etapa 5;
-- até lá a função responde false. Quando a tabela existir, a regra passa a valer
-- automaticamente, sem alterar contas nem seus triggers.
create or replace function public.conta_possui_movimentos(p_conta uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_existe boolean := false;
begin
  if to_regclass('public.movimentos') is null then
    return false;
  end if;
  execute 'select exists (select 1 from public.movimentos where conta_id = $1)' into v_existe using p_conta;
  return v_existe;
end;
$$;

-- Regras de integridade que não dependem da interface.
create or replace function public.tg_contas_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.tipo <> old.tipo then
    raise exception 'O tipo da conta não pode ser alterado.' using errcode = 'check_violation';
  end if;
  if new.organizacao_id <> old.organizacao_id then
    raise exception 'A conta não pode mudar de organização.' using errcode = 'check_violation';
  end if;
  if (new.saldo_inicial <> old.saldo_inicial or new.data_inicio <> old.data_inicio)
     and public.conta_possui_movimentos(old.id) then
    raise exception 'Saldo inicial e data de início não podem ser alterados: a conta já possui lançamentos.' using errcode = 'check_violation';
  end if;
  if old.ativo and not new.ativo and public.conta_possui_movimentos(old.id) then
    raise exception 'A conta não pode ser inativada: já possui lançamentos.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger contas_protecao
  before update on public.contas
  for each row execute function public.tg_contas_protecao();

create trigger contas_atualizado_em
  before update on public.contas
  for each row execute function public.tg_atualizado_em();

create trigger contas_auditoria
  after insert or update or delete on public.contas
  for each row execute function public.tg_auditoria();

-- Privilégios: sem DELETE para clientes (conta nunca é excluída fisicamente).
revoke all on public.contas from anon, authenticated;
grant select, insert, update on public.contas to authenticated;
revoke all on function public.conta_possui_movimentos(uuid) from public, anon;
grant execute on function public.conta_possui_movimentos(uuid) to authenticated;
revoke all on function public.tg_contas_protecao() from public, anon, authenticated;

-- RLS
alter table public.contas enable row level security;

create policy contas_select on public.contas
  for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));

create policy contas_insert on public.contas
  for insert to authenticated
  with check (organizacao_id in (select public.minhas_organizacoes()));

create policy contas_update on public.contas
  for update to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()))
  with check (organizacao_id in (select public.minhas_organizacoes()));
