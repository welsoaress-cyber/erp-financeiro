-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0008: PLANOS E CONTRATOS (Etapa 6C)
-- Plano = catálogo de um negócio. Contrato = pessoa contratando um plano.
-- Lançamento pode apontar para um contrato (herda negócio e pessoa).
-- =============================================================================

create type public.periodicidade    as enum ('mensal', 'anual', 'unico');
create type public.status_contrato  as enum ('ativo', 'suspenso', 'encerrado');

create table public.planos (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  nome           text not null check (char_length(btrim(nome)) between 1 and 80),
  descricao      text check (descricao is null or char_length(descricao) <= 300),
  valor_tabela   numeric(14,2) not null default 0 check (valor_tabela >= 0),
  periodicidade  public.periodicidade not null default 'mensal',
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create index planos_negocio_idx on public.planos (negocio_id);
create unique index planos_nome_unico_idx on public.planos (negocio_id, lower(btrim(nome)));
comment on table public.planos is 'Catálogo de planos/serviços de um negócio, com preço de tabela.';

create table public.contratos (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  pessoa_id      uuid not null references public.pessoas (id) on delete restrict,
  plano_id       uuid not null references public.planos (id) on delete restrict,
  codigo         integer not null,
  valor          numeric(14,2) not null check (valor >= 0),
  periodicidade  public.periodicidade not null,
  data_inicio    date not null default current_date,
  data_fim       date,
  dia_vencimento smallint not null default 10 check (dia_vencimento between 1 and 31),
  status         public.status_contrato not null default 'ativo',
  observacao     text check (observacao is null or char_length(observacao) <= 500),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (negocio_id, codigo),
  check ((status = 'encerrado') = (data_fim is not null)),
  check (data_fim is null or data_fim >= data_inicio)
);
create index contratos_pessoa_idx on public.contratos (pessoa_id);
create index contratos_negocio_status_idx on public.contratos (negocio_id, status);
comment on table public.contratos is 'Pessoa contratando um plano de um negócio. Código sequencial por negócio. Encerrado é imutável.';

alter table public.lancamentos add column contrato_id uuid references public.contratos (id) on delete restrict;
create index lancamentos_contrato_idx on public.lancamentos (contrato_id);

-- -----------------------------------------------------------------------------
-- Planos: negócio da mesma organização e ativo ao criar/reativar; negócio imutável
-- -----------------------------------------------------------------------------
create or replace function public.tg_planos_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and (new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id) then
    raise exception 'O plano não pode mudar de negócio.' using errcode = 'check_violation';
  end if;
  perform public.validar_negocio(new.negocio_id, new.organizacao_id, tg_op = 'INSERT' or (new.ativo and not old.ativo));
  return new;
end;
$$;
create trigger planos_protecao before insert or update on public.planos for each row execute function public.tg_planos_protecao();
create trigger planos_atualizado_em before update on public.planos for each row execute function public.tg_atualizado_em();
create trigger planos_auditoria after insert or update or delete on public.planos for each row execute function public.tg_auditoria();

-- -----------------------------------------------------------------------------
-- Contratos
-- -----------------------------------------------------------------------------
create or replace function public.tg_contratos_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  pl public.planos%rowtype;
  pe public.pessoas%rowtype;
begin
  if tg_op = 'INSERT' then
    select * into pl from public.planos where id = new.plano_id;
    if not found or pl.organizacao_id <> new.organizacao_id then
      raise exception 'Plano inválido.' using errcode = 'check_violation';
    end if;
    if pl.negocio_id <> new.negocio_id then
      raise exception 'O plano não pertence a este negócio.' using errcode = 'check_violation';
    end if;
    if not pl.ativo then
      raise exception 'O plano está inativo.' using errcode = 'check_violation';
    end if;
    select * into pe from public.pessoas where id = new.pessoa_id;
    if not found or pe.organizacao_id <> new.organizacao_id then
      raise exception 'Pessoa inválida.' using errcode = 'check_violation';
    end if;
    if not pe.ativo then
      raise exception 'A pessoa está inativa.' using errcode = 'check_violation';
    end if;
    perform public.validar_negocio(new.negocio_id, new.organizacao_id, true);
    if new.status = 'encerrado' then
      raise exception 'Um contrato não pode ser criado já encerrado.' using errcode = 'check_violation';
    end if;
    -- código sequencial por negócio (lock evita colisão em concorrência)
    perform pg_advisory_xact_lock(hashtext('contratos:' || new.negocio_id::text));
    select coalesce(max(codigo), 0) + 1 into new.codigo from public.contratos where negocio_id = new.negocio_id;
    return new;
  end if;

  -- UPDATE
  if old.status = 'encerrado' then
    raise exception 'Contrato encerrado não pode ser alterado.' using errcode = 'check_violation';
  end if;
  if new.pessoa_id <> old.pessoa_id or new.negocio_id <> old.negocio_id or new.plano_id <> old.plano_id
     or new.organizacao_id <> old.organizacao_id or new.codigo <> old.codigo then
    raise exception 'Pessoa, negócio, plano e código do contrato não podem ser alterados. Encerre e crie outro.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- Ao abrir contrato, garante o vínculo "cliente" da pessoa com o negócio.
create or replace function public.tg_contratos_vinculo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  insert into public.pessoa_negocio_vinculos (organizacao_id, pessoa_id, negocio_id, papel)
  values (new.organizacao_id, new.pessoa_id, new.negocio_id, 'cliente')
  on conflict (pessoa_id, negocio_id, papel) do update set ativo = true;
  return new;
end;
$$;

create trigger contratos_protecao before insert or update on public.contratos for each row execute function public.tg_contratos_protecao();
create trigger contratos_vinculo after insert on public.contratos for each row execute function public.tg_contratos_vinculo();
create trigger contratos_atualizado_em before update on public.contratos for each row execute function public.tg_atualizado_em();
create trigger contratos_auditoria after insert or update or delete on public.contratos for each row execute function public.tg_auditoria();

-- Negócio e pessoa com contratos vigentes não podem ser inativados
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
    if exists (select 1 from public.contratos c where c.negocio_id = old.id and c.status <> 'encerrado') then
      raise exception 'O negócio não pode ser inativado: possui contratos vigentes.' using errcode = 'check_violation';
    end if;
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

create or replace function public.tg_pessoas_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.nome := btrim(new.nome);
  new.email := nullif(lower(btrim(coalesce(new.email, ''))), '');
  new.documento := nullif(regexp_replace(coalesce(new.documento, ''), '[^0-9]', '', 'g'), '');
  new.telefone := nullif(regexp_replace(coalesce(new.telefone, ''), '[^0-9]', '', 'g'), '');
  if tg_op = 'UPDATE' then
    if new.organizacao_id <> old.organizacao_id then
      raise exception 'A pessoa não pode mudar de organização.' using errcode = 'check_violation';
    end if;
    if old.ativo and not new.ativo then
      if exists (select 1 from public.contratos c where c.pessoa_id = old.id and c.status <> 'encerrado') then
        raise exception 'A pessoa não pode ser inativada: possui contratos vigentes.' using errcode = 'check_violation';
      end if;
      if exists (select 1 from public.pessoa_negocio_vinculos v where v.pessoa_id = old.id and v.ativo) then
        raise exception 'A pessoa não pode ser inativada: possui vínculos ativos com negócios.' using errcode = 'check_violation';
      end if;
      if exists (select 1 from public.lancamentos l where l.pessoa_id = old.id and l.status = 'previsto') then
        raise exception 'A pessoa não pode ser inativada: possui lançamentos previstos pendentes.' using errcode = 'check_violation';
      end if;
    end if;
  end if;
  return new;
end;
$$;

-- Lançamentos: contrato herda negócio e pessoa; divergência é erro; transferência sem contrato
create or replace function public.tg_lancamentos_contrato()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  c public.contratos%rowtype;
begin
  if new.contrato_id is null then return new; end if;
  if new.tipo = 'transferencia' then
    raise exception 'Transferência não pode ter contrato.' using errcode = 'check_violation';
  end if;
  select * into c from public.contratos where id = new.contrato_id;
  if not found or c.organizacao_id <> new.organizacao_id then
    raise exception 'Contrato inválido.' using errcode = 'check_violation';
  end if;
  new.negocio_id := coalesce(new.negocio_id, c.negocio_id);
  new.pessoa_id  := coalesce(new.pessoa_id, c.pessoa_id);
  if new.negocio_id <> c.negocio_id then
    raise exception 'O negócio do lançamento difere do negócio do contrato.' using errcode = 'check_violation';
  end if;
  if new.pessoa_id <> c.pessoa_id then
    raise exception 'A pessoa do lançamento difere da pessoa do contrato.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
-- Precisa rodar ANTES dos triggers de negócio/pessoa (ordem alfabética dos nomes): "lancamentos_a_contrato"
create trigger lancamentos_a_contrato before insert or update on public.lancamentos for each row execute function public.tg_lancamentos_contrato();

-- -----------------------------------------------------------------------------
-- Motor: p_contrato_id (13º parâmetro)
-- -----------------------------------------------------------------------------
drop function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid);
drop function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid);

create function public.criar_lancamento(
  p_tipo text, p_descricao text, p_valor numeric, p_data_competencia date,
  p_data_vencimento date default null, p_data_efetivacao date default null,
  p_conta_id uuid default null, p_conta_destino_id uuid default null,
  p_categoria_id uuid default null, p_observacao text default null,
  p_negocio_id uuid default null, p_pessoa_id uuid default null, p_contrato_id uuid default null
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
    status, conta_id, conta_destino_id, categoria_id, observacao, negocio_id, pessoa_id, contrato_id
  ) values (
    v_org, p_tipo::public.tipo_lancamento, btrim(p_descricao), p_valor, p_data_competencia,
    coalesce(p_data_vencimento, p_data_competencia), p_data_efetivacao,
    (case when p_data_efetivacao is null then 'previsto' else 'efetivado' end)::public.status_lancamento,
    p_conta_id, p_conta_destino_id, p_categoria_id, nullif(btrim(coalesce(p_observacao, '')), ''), p_negocio_id, p_pessoa_id, p_contrato_id
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
  p_negocio_id uuid default null, p_pessoa_id uuid default null, p_contrato_id uuid default null
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
    negocio_id       = p_negocio_id,
    pessoa_id        = p_pessoa_id,
    contrato_id      = p_contrato_id
  where id = p_id
  returning * into l;
  perform public.gerar_movimentos(l.id);
  return l;
end;
$$;

-- -----------------------------------------------------------------------------
-- Views
-- -----------------------------------------------------------------------------
-- Rentabilidade por contrato: só lançamentos efetivados vinculados ao contrato.
create view public.vw_resultado_por_contrato
with (security_invoker = true) as
select c.id as contrato_id, c.organizacao_id, c.negocio_id, c.pessoa_id, c.plano_id, c.codigo, c.status, c.valor, c.periodicidade,
       c.data_inicio, c.data_fim,
       coalesce(sum(l.valor) filter (where l.tipo = 'receita'), 0)::numeric(14,2) as receitas,
       coalesce(sum(l.valor) filter (where l.tipo = 'despesa'), 0)::numeric(14,2) as despesas,
       (coalesce(sum(l.valor) filter (where l.tipo = 'receita'), 0) - coalesce(sum(l.valor) filter (where l.tipo = 'despesa'), 0))::numeric(14,2) as resultado,
       count(l.id) as lancamentos,
       min(l.data_competencia) as primeiro_lancamento,
       max(l.data_competencia) as ultimo_lancamento
from public.contratos c
left join public.lancamentos l on l.contrato_id = c.id and l.status = 'efetivado'
group by c.id;

-- Receita recorrente mensal (MRR) por negócio: contratos ativos; anual/12; único não conta.
create view public.vw_receita_recorrente
with (security_invoker = true) as
select n.id as negocio_id, n.organizacao_id, n.nome as negocio,
       count(c.id) filter (where c.status = 'ativo') as contratos_ativos,
       count(c.id) filter (where c.status = 'suspenso') as contratos_suspensos,
       coalesce(sum(case c.periodicidade when 'mensal' then c.valor when 'anual' then c.valor / 12 else 0 end) filter (where c.status = 'ativo'), 0)::numeric(14,2) as mrr
from public.negocios n
left join public.contratos c on c.negocio_id = n.id
group by n.id;

-- -----------------------------------------------------------------------------
-- Privilégios e RLS
-- -----------------------------------------------------------------------------
revoke all on public.planos from anon, authenticated;
revoke all on public.contratos from anon, authenticated;
grant select, insert, update on public.planos to authenticated;
grant select, insert, update on public.contratos to authenticated;
grant select on public.vw_resultado_por_contrato, public.vw_receita_recorrente to authenticated;
revoke all on function public.tg_planos_protecao() from public, anon, authenticated;
revoke all on function public.tg_contratos_protecao() from public, anon, authenticated;
revoke all on function public.tg_contratos_vinculo() from public, anon, authenticated;
revoke all on function public.tg_lancamentos_contrato() from public, anon, authenticated;
revoke all on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid) from public, anon;
revoke all on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid) from public, anon;
grant execute on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid) to authenticated;
grant execute on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid) to authenticated;

alter table public.planos enable row level security;
alter table public.contratos enable row level security;
create policy planos_select on public.planos for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy planos_insert on public.planos for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy planos_update on public.planos for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy contratos_select on public.contratos for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy contratos_insert on public.contratos for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy contratos_update on public.contratos for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
