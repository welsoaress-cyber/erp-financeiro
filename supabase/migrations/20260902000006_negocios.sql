-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0006: NEGÓCIOS (Etapa 6A)
-- Dimensão "negócio" em lançamentos e contas. NULL = pessoal/central.
-- O motor financeiro não muda de modelo: só ganha a etiqueta negocio_id.
-- =============================================================================

create table public.negocios (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  nome           text not null check (char_length(btrim(nome)) between 1 and 60),
  slug           text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 40),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create index negocios_organizacao_idx on public.negocios (organizacao_id);
create unique index negocios_nome_unico_idx on public.negocios (organizacao_id, lower(btrim(nome)));
create unique index negocios_slug_unico_idx on public.negocios (organizacao_id, slug);
comment on table public.negocios is 'Unidades de negócio da organização (SERVNET, SERVIDOR…). Lançamento/conta sem negócio = pessoal.';

-- Dimensão nos lançamentos e nas contas
alter table public.lancamentos add column negocio_id uuid references public.negocios (id) on delete restrict;
alter table public.contas      add column negocio_id uuid references public.negocios (id) on delete restrict;
create index lancamentos_negocio_idx on public.lancamentos (organizacao_id, negocio_id);
create index contas_negocio_idx on public.contas (negocio_id);

-- -----------------------------------------------------------------------------
-- Proteção de negócios
-- -----------------------------------------------------------------------------
create or replace function public.tg_negocios_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.organizacao_id <> old.organizacao_id then
    raise exception 'O negócio não pode mudar de organização.' using errcode = 'check_violation';
  end if;
  if old.ativo and not new.ativo then
    if exists (select 1 from public.lancamentos l where l.negocio_id = old.id and l.status = 'previsto') then
      raise exception 'O negócio não pode ser inativado: possui lançamentos previstos pendentes.' using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.contas c where c.negocio_id = old.id and c.ativo) then
      raise exception 'O negócio não pode ser inativado: possui contas ativas vinculadas.' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

create trigger negocios_protecao
  before update on public.negocios
  for each row execute function public.tg_negocios_protecao();
create trigger negocios_atualizado_em
  before update on public.negocios
  for each row execute function public.tg_atualizado_em();
create trigger negocios_auditoria
  after insert or update or delete on public.negocios
  for each row execute function public.tg_auditoria();

-- Valida o vínculo de um registro a um negócio (mesma organização; ativo ao vincular).
create or replace function public.validar_negocio(p_negocio uuid, p_organizacao uuid, p_exigir_ativo boolean)
returns void
language plpgsql
stable
set search_path = public
as $$
declare
  n public.negocios%rowtype;
begin
  if p_negocio is null then return; end if;
  select * into n from public.negocios where id = p_negocio;
  if not found or n.organizacao_id <> p_organizacao then
    raise exception 'Negócio inválido.' using errcode = 'check_violation';
  end if;
  if p_exigir_ativo and not n.ativo then
    raise exception 'O negócio está inativo.' using errcode = 'check_violation';
  end if;
end;
$$;

-- Contas: valida negócio ao vincular/trocar
create or replace function public.tg_contas_negocio()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform public.validar_negocio(new.negocio_id, new.organizacao_id,
    tg_op = 'INSERT' or new.negocio_id is distinct from old.negocio_id);
  return new;
end;
$$;
create trigger contas_negocio
  before insert or update on public.contas
  for each row execute function public.tg_contas_negocio();

-- Lançamentos: valida negócio ao vincular/trocar (dentro do motor)
create or replace function public.tg_lancamentos_negocio()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform public.validar_negocio(new.negocio_id, new.organizacao_id,
    tg_op = 'INSERT' or new.negocio_id is distinct from old.negocio_id);
  return new;
end;
$$;
create trigger lancamentos_negocio
  before insert or update on public.lancamentos
  for each row execute function public.tg_lancamentos_negocio();

-- -----------------------------------------------------------------------------
-- Motor: criar/atualizar ganham p_negocio_id (assinatura nova; a antiga é removida)
-- -----------------------------------------------------------------------------
drop function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text);
drop function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text);

create function public.criar_lancamento(
  p_tipo text, p_descricao text, p_valor numeric, p_data_competencia date,
  p_data_vencimento date default null, p_data_efetivacao date default null,
  p_conta_id uuid default null, p_conta_destino_id uuid default null,
  p_categoria_id uuid default null, p_observacao text default null,
  p_negocio_id uuid default null
)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
  l public.lancamentos%rowtype;
begin
  select organizacao_id into v_org from public.contas where id = p_conta_id;
  perform public.exigir_membro(v_org);
  perform set_config('erp.motor', 'on', true);

  insert into public.lancamentos (
    organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao,
    status, conta_id, conta_destino_id, categoria_id, observacao, negocio_id
  ) values (
    v_org, p_tipo::public.tipo_lancamento, btrim(p_descricao), p_valor, p_data_competencia,
    coalesce(p_data_vencimento, p_data_competencia), p_data_efetivacao,
    (case when p_data_efetivacao is null then 'previsto' else 'efetivado' end)::public.status_lancamento,
    p_conta_id, p_conta_destino_id, p_categoria_id, nullif(btrim(coalesce(p_observacao, '')), ''), p_negocio_id
  ) returning * into l;

  perform public.gerar_movimentos(l.id);
  return l;
end;
$$;

create function public.atualizar_lancamento(
  p_id uuid, p_descricao text, p_valor numeric, p_data_competencia date,
  p_data_vencimento date default null, p_data_efetivacao date default null,
  p_conta_id uuid default null, p_conta_destino_id uuid default null,
  p_categoria_id uuid default null, p_observacao text default null,
  p_negocio_id uuid default null
)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  perform set_config('erp.motor', 'on', true);

  update public.lancamentos set
    descricao        = btrim(p_descricao),
    valor            = p_valor,
    data_competencia = p_data_competencia,
    data_vencimento  = coalesce(p_data_vencimento, p_data_competencia),
    data_efetivacao  = p_data_efetivacao,
    status           = (case when p_data_efetivacao is null then 'previsto' else 'efetivado' end)::public.status_lancamento,
    conta_id         = coalesce(p_conta_id, conta_id),
    conta_destino_id = case when tipo = 'transferencia' then coalesce(p_conta_destino_id, conta_destino_id) else null end,
    categoria_id     = case when tipo = 'transferencia' then null else coalesce(p_categoria_id, categoria_id) end,
    observacao       = nullif(btrim(coalesce(p_observacao, '')), ''),
    negocio_id       = p_negocio_id
  where id = p_id
  returning * into l;

  perform public.gerar_movimentos(l.id);
  return l;
end;
$$;

-- -----------------------------------------------------------------------------
-- Views
-- -----------------------------------------------------------------------------
create or replace view public.vw_saldo_contas
with (security_invoker = true) as
select c.id, c.organizacao_id, c.nome, c.tipo, c.ativo, c.saldo_inicial, c.data_inicio,
       c.saldo_inicial + coalesce(sum(m.valor), 0)::numeric(14,2) as saldo,
       count(m.id) as movimentos,
       c.negocio_id
from public.contas c
left join public.movimentos m on m.conta_id = c.id
group by c.id;

-- Resultado mensal por negócio (negocio_id nulo = pessoal). Só efetivados, sem transferências.
create view public.vw_resultado_mensal_negocio
with (security_invoker = true) as
select organizacao_id,
       negocio_id,
       date_trunc('month', data_competencia)::date as mes,
       coalesce(sum(valor) filter (where tipo = 'receita'), 0)::numeric(14,2) as receitas,
       coalesce(sum(valor) filter (where tipo = 'despesa'), 0)::numeric(14,2) as despesas,
       (coalesce(sum(valor) filter (where tipo = 'receita'), 0) - coalesce(sum(valor) filter (where tipo = 'despesa'), 0))::numeric(14,2) as resultado
from public.lancamentos
where status = 'efetivado'
group by organizacao_id, negocio_id, date_trunc('month', data_competencia);

-- -----------------------------------------------------------------------------
-- Privilégios e RLS
-- -----------------------------------------------------------------------------
revoke all on public.negocios from anon, authenticated;
grant select, insert, update on public.negocios to authenticated;
grant select on public.vw_resultado_mensal_negocio to authenticated;
revoke all on function public.tg_negocios_protecao() from public, anon, authenticated;
revoke all on function public.tg_contas_negocio() from public, anon, authenticated;
revoke all on function public.tg_lancamentos_negocio() from public, anon, authenticated;
revoke all on function public.validar_negocio(uuid, uuid, boolean) from public, anon;
grant execute on function public.validar_negocio(uuid, uuid, boolean) to authenticated; -- chamada por trigger que roda como o usuário
revoke all on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid) from public, anon;
revoke all on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid) from public, anon;
grant execute on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid) to authenticated;
grant execute on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid) to authenticated;

alter table public.negocios enable row level security;

create policy negocios_select on public.negocios
  for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));

create policy negocios_insert on public.negocios
  for insert to authenticated
  with check (organizacao_id in (select public.minhas_organizacoes()));

create policy negocios_update on public.negocios
  for update to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()))
  with check (organizacao_id in (select public.minhas_organizacoes()));
