-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0005: MOTOR FINANCEIRO (LANÇAMENTOS)
-- Lançamento = evento. Movimento = efeito em uma conta. Saldo = view derivada.
-- Clientes só LEEM lancamentos/movimentos; toda escrita passa pelas funções
-- do motor (criar/atualizar/efetivar/cancelar/excluir_lancamento).
-- =============================================================================

create type public.tipo_lancamento   as enum ('receita', 'despesa', 'transferencia');
create type public.status_lancamento as enum ('previsto', 'efetivado', 'cancelado');
create type public.origem_lancamento as enum ('manual', 'sistema');

-- -----------------------------------------------------------------------------
-- 1. Tabelas
-- -----------------------------------------------------------------------------
create table public.lancamentos (
  id                  uuid primary key default gen_random_uuid(),
  organizacao_id      uuid not null references public.organizacoes (id) on delete restrict,
  tipo                public.tipo_lancamento not null,
  descricao           text not null check (char_length(btrim(descricao)) between 1 and 140),
  valor               numeric(14,2) not null check (valor > 0),
  data_competencia    date not null,
  data_vencimento     date not null,
  data_efetivacao     date,
  status              public.status_lancamento not null default 'previsto',
  conta_id            uuid not null references public.contas (id) on delete restrict,
  conta_destino_id    uuid references public.contas (id) on delete restrict,
  categoria_id        uuid references public.categorias (id) on delete restrict,
  observacao          text check (observacao is null or char_length(observacao) <= 500),
  origem              public.origem_lancamento not null default 'manual',
  cancelado_em        timestamptz,
  motivo_cancelamento text check (motivo_cancelamento is null or char_length(motivo_cancelamento) <= 200),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  -- transferência: sem categoria, com destino distinto; receita/despesa: com categoria, sem destino
  check ((tipo = 'transferencia') = (categoria_id is null)),
  check ((tipo = 'transferencia') = (conta_destino_id is not null)),
  check (conta_destino_id is distinct from conta_id),
  -- efetivado <=> tem data de efetivação; cancelado <=> tem cancelado_em
  check ((status = 'efetivado') = (data_efetivacao is not null)),
  check ((status = 'cancelado') = (cancelado_em is not null))
);
create index lancamentos_org_competencia_idx on public.lancamentos (organizacao_id, data_competencia desc);
create index lancamentos_org_status_idx on public.lancamentos (organizacao_id, status);
create index lancamentos_conta_idx on public.lancamentos (conta_id);
create index lancamentos_categoria_idx on public.lancamentos (categoria_id);
comment on table public.lancamentos is 'Evento financeiro. Escrita somente pelas funções do motor.';

create table public.movimentos (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  lancamento_id  uuid not null references public.lancamentos (id) on delete restrict,
  conta_id       uuid not null references public.contas (id) on delete restrict,
  valor          numeric(14,2) not null check (valor <> 0),
  data           date not null,
  criado_em      timestamptz not null default now()
);
create index movimentos_conta_data_idx on public.movimentos (conta_id, data);
create index movimentos_lancamento_idx on public.movimentos (lancamento_id);
comment on table public.movimentos is 'Efeito de um lançamento efetivado em uma conta (valor com sinal). Escrita somente pelo motor.';

-- -----------------------------------------------------------------------------
-- 2. Proteção: só o motor escreve (flag de sessão) + validações
-- -----------------------------------------------------------------------------
create or replace function public.motor_ativo()
returns boolean
language sql
stable
set search_path = public
as $$ select coalesce(current_setting('erp.motor', true), '') = 'on' $$;

create or replace function public.tg_lancamentos_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_conta   public.contas%rowtype;
  v_destino public.contas%rowtype;
  v_cat     public.categorias%rowtype;
begin
  if not public.motor_ativo() then
    raise exception 'Lançamentos só podem ser gravados pelas funções do motor financeiro.' using errcode = 'insufficient_privilege';
  end if;

  if tg_op = 'DELETE' then
    if old.status <> 'previsto' then
      raise exception 'Somente lançamentos previstos podem ser excluídos. Use o cancelamento.' using errcode = 'check_violation';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if old.status = 'cancelado' then
      raise exception 'Lançamento cancelado não pode ser alterado.' using errcode = 'check_violation';
    end if;
    if new.organizacao_id <> old.organizacao_id then
      raise exception 'O lançamento não pode mudar de organização.' using errcode = 'check_violation';
    end if;
    if new.tipo <> old.tipo then
      raise exception 'O tipo do lançamento não pode ser alterado. Cancele e crie outro.' using errcode = 'check_violation';
    end if;
  end if;

  if new.data_vencimento < new.data_competencia - interval '1 year' then
    raise exception 'Data de vencimento inválida.' using errcode = 'check_violation';
  end if;

  select * into v_conta from public.contas where id = new.conta_id;
  if not found or v_conta.organizacao_id <> new.organizacao_id then
    raise exception 'Conta inválida.' using errcode = 'check_violation';
  end if;
  if not v_conta.ativo and (tg_op = 'INSERT' or new.conta_id <> old.conta_id) then
    raise exception 'A conta está inativa.' using errcode = 'check_violation';
  end if;

  if new.conta_destino_id is not null then
    select * into v_destino from public.contas where id = new.conta_destino_id;
    if not found or v_destino.organizacao_id <> new.organizacao_id then
      raise exception 'Conta de destino inválida.' using errcode = 'check_violation';
    end if;
    if not v_destino.ativo and (tg_op = 'INSERT' or new.conta_destino_id is distinct from old.conta_destino_id) then
      raise exception 'A conta de destino está inativa.' using errcode = 'check_violation';
    end if;
  end if;

  if new.categoria_id is not null then
    select * into v_cat from public.categorias where id = new.categoria_id;
    if not found or v_cat.organizacao_id <> new.organizacao_id then
      raise exception 'Categoria inválida.' using errcode = 'check_violation';
    end if;
    if v_cat.tipo::text <> new.tipo::text then
      raise exception 'A categoria deve ser do mesmo tipo do lançamento (receita ou despesa).' using errcode = 'check_violation';
    end if;
    if not v_cat.ativo and (tg_op = 'INSERT' or new.categoria_id is distinct from old.categoria_id) then
      raise exception 'A categoria está inativa.' using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.tg_movimentos_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not public.motor_ativo() then
    raise exception 'Movimentos só podem ser gravados pelo motor financeiro.' using errcode = 'insufficient_privilege';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger lancamentos_protecao
  before insert or update or delete on public.lancamentos
  for each row execute function public.tg_lancamentos_protecao();
create trigger lancamentos_atualizado_em
  before update on public.lancamentos
  for each row execute function public.tg_atualizado_em();
create trigger lancamentos_auditoria
  after insert or update or delete on public.lancamentos
  for each row execute function public.tg_auditoria();

create trigger movimentos_protecao
  before insert or update or delete on public.movimentos
  for each row execute function public.tg_movimentos_protecao();
create trigger movimentos_auditoria
  after insert or update or delete on public.movimentos
  for each row execute function public.tg_auditoria();

-- -----------------------------------------------------------------------------
-- 3. Motor
-- -----------------------------------------------------------------------------

-- (Re)gera os movimentos de um lançamento a partir do seu estado atual.
create or replace function public.gerar_movimentos(p_id uuid)
returns void
language plpgsql
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
begin
  select * into l from public.lancamentos where id = p_id;
  delete from public.movimentos where lancamento_id = l.id;
  if l.status <> 'efetivado' then
    return;
  end if;
  if l.tipo = 'receita' then
    insert into public.movimentos (organizacao_id, lancamento_id, conta_id, valor, data)
    values (l.organizacao_id, l.id, l.conta_id, l.valor, l.data_efetivacao);
  elsif l.tipo = 'despesa' then
    insert into public.movimentos (organizacao_id, lancamento_id, conta_id, valor, data)
    values (l.organizacao_id, l.id, l.conta_id, -l.valor, l.data_efetivacao);
  else
    insert into public.movimentos (organizacao_id, lancamento_id, conta_id, valor, data)
    values (l.organizacao_id, l.id, l.conta_id, -l.valor, l.data_efetivacao),
           (l.organizacao_id, l.id, l.conta_destino_id, l.valor, l.data_efetivacao);
  end if;
end;
$$;

-- Garante que o usuário autenticado pertence à organização.
create or replace function public.exigir_membro(p_organizacao uuid)
returns void
language plpgsql
stable
set search_path = public
as $$
begin
  if p_organizacao is null or p_organizacao not in (select public.minhas_organizacoes()) then
    raise exception 'Sem permissão para esta organização.' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

create or replace function public.criar_lancamento(
  p_tipo text, p_descricao text, p_valor numeric, p_data_competencia date,
  p_data_vencimento date default null, p_data_efetivacao date default null,
  p_conta_id uuid default null, p_conta_destino_id uuid default null,
  p_categoria_id uuid default null, p_observacao text default null
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
    status, conta_id, conta_destino_id, categoria_id, observacao
  ) values (
    v_org, p_tipo::public.tipo_lancamento, btrim(p_descricao), p_valor, p_data_competencia,
    coalesce(p_data_vencimento, p_data_competencia), p_data_efetivacao,
    (case when p_data_efetivacao is null then 'previsto' else 'efetivado' end)::public.status_lancamento,
    p_conta_id, p_conta_destino_id, p_categoria_id, nullif(btrim(coalesce(p_observacao, '')), '')
  ) returning * into l;

  perform public.gerar_movimentos(l.id);
  return l;
end;
$$;

-- Edição (auditada) de lançamento previsto ou efetivado. Tipo não muda.
create or replace function public.atualizar_lancamento(
  p_id uuid, p_descricao text, p_valor numeric, p_data_competencia date,
  p_data_vencimento date default null, p_data_efetivacao date default null,
  p_conta_id uuid default null, p_conta_destino_id uuid default null,
  p_categoria_id uuid default null, p_observacao text default null
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
    observacao       = nullif(btrim(coalesce(p_observacao, '')), '')
  where id = p_id
  returning * into l;

  perform public.gerar_movimentos(l.id);
  return l;
end;
$$;

create or replace function public.efetivar_lancamento(p_id uuid, p_data_efetivacao date default current_date)
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
  if l.status <> 'previsto' then
    raise exception 'Somente lançamentos previstos podem ser efetivados.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.lancamentos set status = 'efetivado', data_efetivacao = p_data_efetivacao where id = p_id returning * into l;
  perform public.gerar_movimentos(l.id);
  return l;
end;
$$;

create or replace function public.cancelar_lancamento(p_id uuid, p_motivo text default null)
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
  if l.status = 'cancelado' then
    raise exception 'Lançamento já cancelado.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.lancamentos
     set status = 'cancelado', cancelado_em = now(), motivo_cancelamento = nullif(btrim(coalesce(p_motivo, '')), ''),
         data_efetivacao = null
   where id = p_id returning * into l;
  perform public.gerar_movimentos(l.id); -- remove os movimentos (auditados)
  return l;
end;
$$;

create or replace function public.excluir_lancamento(p_id uuid)
returns void
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
  delete from public.lancamentos where id = p_id; -- trigger só permite previsto
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Views derivadas (RLS do chamador)
-- -----------------------------------------------------------------------------
create view public.vw_saldo_contas
with (security_invoker = true) as
select c.id, c.organizacao_id, c.nome, c.tipo, c.ativo, c.saldo_inicial, c.data_inicio,
       c.saldo_inicial + coalesce(sum(m.valor), 0)::numeric(14,2) as saldo,
       count(m.id) as movimentos
from public.contas c
left join public.movimentos m on m.conta_id = c.id
group by c.id;

create view public.vw_resultado_mensal
with (security_invoker = true) as
select organizacao_id,
       date_trunc('month', data_competencia)::date as mes,
       coalesce(sum(valor) filter (where tipo = 'receita'), 0)::numeric(14,2) as receitas,
       coalesce(sum(valor) filter (where tipo = 'despesa'), 0)::numeric(14,2) as despesas,
       (coalesce(sum(valor) filter (where tipo = 'receita'), 0) - coalesce(sum(valor) filter (where tipo = 'despesa'), 0))::numeric(14,2) as resultado
from public.lancamentos
where status = 'efetivado'
group by organizacao_id, date_trunc('month', data_competencia);

-- -----------------------------------------------------------------------------
-- 5. Privilégios e RLS
-- -----------------------------------------------------------------------------
revoke all on public.lancamentos from anon, authenticated;
revoke all on public.movimentos  from anon, authenticated;
grant select on public.lancamentos to authenticated;
grant select on public.movimentos  to authenticated;
grant select on public.vw_saldo_contas, public.vw_resultado_mensal to authenticated;

revoke all on function public.motor_ativo() from public, anon;
revoke all on function public.gerar_movimentos(uuid) from public, anon, authenticated;
revoke all on function public.exigir_membro(uuid) from public, anon, authenticated;
revoke all on function public.tg_lancamentos_protecao() from public, anon, authenticated;
revoke all on function public.tg_movimentos_protecao() from public, anon, authenticated;
revoke all on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text) from public, anon;
revoke all on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text) from public, anon;
revoke all on function public.efetivar_lancamento(uuid, date) from public, anon;
revoke all on function public.cancelar_lancamento(uuid, text) from public, anon;
revoke all on function public.excluir_lancamento(uuid) from public, anon;
grant execute on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text) to authenticated;
grant execute on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text) to authenticated;
grant execute on function public.efetivar_lancamento(uuid, date) to authenticated;
grant execute on function public.cancelar_lancamento(uuid, text) to authenticated;
grant execute on function public.excluir_lancamento(uuid) to authenticated;

alter table public.lancamentos enable row level security;
alter table public.movimentos  enable row level security;

create policy lancamentos_select on public.lancamentos
  for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));

create policy movimentos_select on public.movimentos
  for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));
