-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0015: REFUNDAÇÃO DE CONTRATOS E FATURAMENTO (correção de produção)
-- Diagnóstico de 03/09/2026: em produção, planos/contratos/faturamentos/
-- faturamento_execucoes foram criadas por outra ferramenta (created_at,
-- sem organizacao_id, sem triggers, sem RLS do repositório) e as migrations
-- 0008 e 0009 nunca foram aplicadas. As tabelas estão vazias.
-- Esta migration:
--   1. só roda se contratos NÃO tiver organizacao_id (esquema externo) e se
--      planos/contratos/faturamentos estiverem vazias — caso contrário aborta
--      sem alterar nada;
--   2. remove o esquema externo (tabelas, funções, views, triggers, tipos);
--   3. recria exatamente o conteúdo das migrations 0008 e 0009, exceto o motor
--      de lançamentos (já está na versão da 0012, com 17 parâmetros).
-- Ordem em produção: 0014 → 0015 → 0013 → 0010 (pg_cron) → verificar_tudo.
-- =============================================================================
do $$
declare n_contratos bigint := 0; n_planos bigint := 0; n_fat bigint := 0;
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'contratos' and column_name = 'organizacao_id') then
    raise exception 'Migration 0015: contratos já segue o repositório. Nada foi alterado.';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'contratos') then execute 'select count(*) from public.contratos' into n_contratos; end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'planos') then execute 'select count(*) from public.planos' into n_planos; end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'faturamentos') then execute 'select count(*) from public.faturamentos' into n_fat; end if;
  if n_contratos > 0 or n_planos > 0 or n_fat > 0 then
    raise exception 'Migration 0015: há dados em contratos (%), planos (%) ou faturamentos (%). Nada foi alterado; envie este resultado.', n_contratos, n_planos, n_fat;
  end if;

  -- esquema externo fora
  drop table if exists public.faturamento_execucoes cascade;
  drop table if exists public.faturamentos cascade;
  drop table if exists public.contratos cascade;
  drop table if exists public.planos cascade;
  drop view if exists public.vw_resultado_por_contrato;
  drop view if exists public.vw_receita_recorrente;
  drop view if exists public.vw_faturamentos;
  drop trigger if exists lancamentos_a_contrato on public.lancamentos;
  drop trigger if exists negocios_config on public.negocios;
  drop function if exists public.tg_planos_protecao() cascade;
  drop function if exists public.tg_contratos_protecao() cascade;
  drop function if exists public.tg_contratos_vinculo() cascade;
  drop function if exists public.tg_lancamentos_contrato() cascade;
  drop function if exists public.tg_negocios_config() cascade;
  drop function if exists public.tg_contratos_config() cascade;
  drop function if exists public.tg_faturamentos_protecao() cascade;
  drop function if exists public.data_vencimento_no_mes(date, smallint);
  drop function if exists public.competencias_pendentes(uuid, date);
  drop function if exists public.faturar_contrato(uuid, date);
  drop function if exists public.gerar_faturamento(uuid, date, text);
  drop function if exists public.gerar_faturamento_agora(date);
  drop function if exists public.gerar_faturamento_todas();
  drop function if exists public.trigger_auditoria() cascade;
  drop type if exists public.periodicidade;
  drop type if exists public.status_contrato;
  -- colunas que a 0008/0009 criam (as externas podem não ter chave estrangeira)
  alter table public.lancamentos drop column if exists contrato_id;
  alter table public.negocios drop column if exists conta_padrao_id;
  alter table public.negocios drop column if exists categoria_receita_id;
end $$;

-- =============================================================================
-- Conteúdo da migration 0008 (sem o motor de lançamentos)
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
alter table public.planos enable row level security;
alter table public.contratos enable row level security;
create policy planos_select on public.planos for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy planos_insert on public.planos for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy planos_update on public.planos for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy contratos_select on public.contratos for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy contratos_insert on public.contratos for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy contratos_update on public.contratos for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));

-- =============================================================================
-- Conteúdo da migration 0009
-- =============================================================================
alter type public.origem_lancamento add value if not exists 'faturamento';

-- Configuração padrão por negócio
alter table public.negocios
  add column conta_padrao_id uuid references public.contas (id) on delete restrict,
  add column categoria_receita_id uuid references public.categorias (id) on delete restrict;

-- Configuração por contrato
alter table public.contratos
  add column faturamento_automatico boolean not null default true,
  add column faturar_desde date,
  add column conta_id uuid references public.contas (id) on delete restrict;

-- Registro do que foi faturado: um por contrato e competência
create table public.faturamentos (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  contrato_id    uuid not null references public.contratos (id) on delete restrict,
  competencia    date not null,
  lancamento_id  uuid not null references public.lancamentos (id) on delete restrict,
  gerado_em      timestamptz not null default now(),
  unique (contrato_id, competencia),
  check (competencia = date_trunc('month', competencia)::date)
);
create index faturamentos_contrato_idx on public.faturamentos (contrato_id, competencia desc);
comment on table public.faturamentos is 'Trilha do faturamento recorrente. A unicidade (contrato, competência) impede gerar o mesmo mês duas vezes.';

-- Log de execuções (manual ou agendada)
create table public.faturamento_execucoes (
  id             bigint generated always as identity primary key,
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  executado_em   timestamptz not null default now(),
  origem         text not null check (origem in ('manual', 'agendado')),
  ate            date not null,
  gerados        integer not null default 0,
  pendencias     jsonb not null default '[]'::jsonb
);
create index faturamento_execucoes_org_idx on public.faturamento_execucoes (organizacao_id, executado_em desc);

-- Validações de configuração
create or replace function public.tg_negocios_config()
returns trigger
language plpgsql
set search_path = public
as $$
declare c public.contas%rowtype; k public.categorias%rowtype;
begin
  if new.conta_padrao_id is not null then
    select * into c from public.contas where id = new.conta_padrao_id;
    if not found or c.organizacao_id <> new.organizacao_id then raise exception 'Conta padrão inválida.' using errcode = 'check_violation'; end if;
    if not c.ativo and new.conta_padrao_id is distinct from old.conta_padrao_id then raise exception 'A conta padrão está inativa.' using errcode = 'check_violation'; end if;
  end if;
  if new.categoria_receita_id is not null then
    select * into k from public.categorias where id = new.categoria_receita_id;
    if not found or k.organizacao_id <> new.organizacao_id then raise exception 'Categoria de receita inválida.' using errcode = 'check_violation'; end if;
    if k.tipo <> 'receita' then raise exception 'A categoria padrão deve ser de receita.' using errcode = 'check_violation'; end if;
    if not k.ativo and new.categoria_receita_id is distinct from old.categoria_receita_id then raise exception 'A categoria padrão está inativa.' using errcode = 'check_violation'; end if;
  end if;
  return new;
end;
$$;
create trigger negocios_config before update on public.negocios for each row execute function public.tg_negocios_config();

create or replace function public.tg_contratos_config()
returns trigger
language plpgsql
set search_path = public
as $$
declare c public.contas%rowtype;
begin
  if new.conta_id is not null then
    select * into c from public.contas where id = new.conta_id;
    if not found or c.organizacao_id <> new.organizacao_id then raise exception 'Conta de recebimento inválida.' using errcode = 'check_violation'; end if;
    if not c.ativo and (tg_op = 'INSERT' or new.conta_id is distinct from old.conta_id) then raise exception 'A conta de recebimento está inativa.' using errcode = 'check_violation'; end if;
  end if;
  if new.faturar_desde is null then new.faturar_desde := new.data_inicio; end if;
  return new;
end;
$$;
-- roda antes de contratos_protecao (ordem alfabética): "contratos_a_config"
create trigger contratos_a_config before insert or update on public.contratos for each row execute function public.tg_contratos_config();
update public.contratos set faturar_desde = data_inicio where faturar_desde is null;

-- Faturamentos: só o motor escreve
create or replace function public.tg_faturamentos_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not public.motor_ativo() then
    raise exception 'Faturamentos só podem ser gravados pelo motor financeiro.' using errcode = 'insufficient_privilege';
  end if;
  return coalesce(new, old);
end;
$$;
create trigger faturamentos_protecao before insert or update or delete on public.faturamentos for each row execute function public.tg_faturamentos_protecao();
create trigger faturamentos_auditoria after insert or update or delete on public.faturamentos for each row execute function public.tg_auditoria();

-- -----------------------------------------------------------------------------
-- Motor de faturamento
-- -----------------------------------------------------------------------------

-- Dia de vencimento ajustado ao mês (31 → 28/29/30 quando necessário)
create or replace function public.data_vencimento_no_mes(p_competencia date, p_dia smallint)
returns date
language sql
immutable
set search_path = public
as $$
  select make_date(extract(year from p_competencia)::int, extract(month from p_competencia)::int,
                   least(p_dia, extract(day from (date_trunc('month', p_competencia) + interval '1 month - 1 day'))::int));
$$;

-- Competências devidas de um contrato até p_ate (inclusive o mês de p_ate), ainda não faturadas.
create or replace function public.competencias_pendentes(p_contrato uuid, p_ate date)
returns setof date
language plpgsql
stable
set search_path = public
as $$
declare
  c public.contratos%rowtype;
  v_ini date; v_fim date; v_comp date; v_passo interval;
begin
  select * into c from public.contratos where id = p_contrato;
  if not found or c.status <> 'ativo' or not c.faturamento_automatico then return; end if;
  v_ini := date_trunc('month', coalesce(c.faturar_desde, c.data_inicio))::date;
  v_fim := date_trunc('month', p_ate)::date;
  if c.data_fim is not null then v_fim := least(v_fim, date_trunc('month', c.data_fim)::date); end if;
  if v_ini > v_fim then return; end if;
  if c.periodicidade = 'unico' then
    if not exists (select 1 from public.faturamentos f where f.contrato_id = c.id) then return next v_ini; end if;
    return;
  end if;
  v_passo := case c.periodicidade when 'mensal' then interval '1 month' else interval '1 year' end;
  v_comp := v_ini;
  while v_comp <= v_fim loop
    if not exists (select 1 from public.faturamentos f where f.contrato_id = c.id and f.competencia = v_comp) then
      return next v_comp;
    end if;
    v_comp := (v_comp + v_passo)::date;
  end loop;
end;
$$;

-- Gera os previstos de UM contrato. Devolve quantos gerou; pendência (texto) se faltar configuração.
create or replace function public.faturar_contrato(p_contrato uuid, p_ate date, out gerados integer, out pendencia text)
language plpgsql
set search_path = public
as $$
declare
  c public.contratos%rowtype;
  n public.negocios%rowtype;
  pl public.planos%rowtype;
  v_conta uuid; v_cat uuid; v_comp date; v_venc date; l public.lancamentos%rowtype;
begin
  gerados := 0; pendencia := null;
  select * into c from public.contratos where id = p_contrato;
  if not found or c.status <> 'ativo' or not c.faturamento_automatico then return; end if;
  if not exists (select 1 from public.competencias_pendentes(c.id, p_ate)) then return; end if;
  select * into n from public.negocios where id = c.negocio_id;
  select * into pl from public.planos where id = c.plano_id;
  v_conta := coalesce(c.conta_id, n.conta_padrao_id);
  v_cat := n.categoria_receita_id;
  if v_conta is null then pendencia := 'Sem conta de recebimento (no contrato ou padrão do negócio).'; return; end if;
  if v_cat is null then pendencia := 'Negócio sem categoria de receita padrão.'; return; end if;
  if not exists (select 1 from public.contas where id = v_conta and ativo) then pendencia := 'Conta de recebimento inativa.'; return; end if;
  if not exists (select 1 from public.categorias where id = v_cat and ativo) then pendencia := 'Categoria de receita padrão inativa.'; return; end if;
  if c.valor <= 0 then pendencia := 'Contrato com valor zero.'; return; end if;

  perform set_config('erp.motor', 'on', true);
  for v_comp in select * from public.competencias_pendentes(c.id, p_ate) order by 1 loop
    v_venc := public.data_vencimento_no_mes(v_comp, c.dia_vencimento);
    insert into public.lancamentos (
      organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
      conta_id, categoria_id, origem, negocio_id, pessoa_id, contrato_id
    ) values (
      c.organizacao_id, 'receita',
      left(pl.nome || ' · ' || to_char(v_comp, 'MM/YYYY') || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140),
      c.valor, v_venc, v_venc, null, 'previsto',
      v_conta, v_cat, 'faturamento', c.negocio_id, c.pessoa_id, c.id
    ) returning * into l;
    insert into public.faturamentos (organizacao_id, contrato_id, competencia, lancamento_id) values (c.organizacao_id, c.id, v_comp, l.id);
    gerados := gerados + 1;
  end loop;
end;
$$;

-- Gera para todos os contratos ativos de uma organização e registra a execução.
create or replace function public.gerar_faturamento(p_organizacao uuid, p_ate date, p_origem text)
returns public.faturamento_execucoes
language plpgsql
security definer
set search_path = public
as $$
declare
  r record; res record; v_total integer := 0; v_pend jsonb := '[]'::jsonb; e public.faturamento_execucoes%rowtype;
begin
  for r in select c.id, c.codigo, c.negocio_id from public.contratos c
           where c.organizacao_id = p_organizacao and c.status = 'ativo' and c.faturamento_automatico
           order by c.negocio_id, c.codigo loop
    select * into res from public.faturar_contrato(r.id, p_ate);
    v_total := v_total + coalesce(res.gerados, 0);
    if res.pendencia is not null then
      v_pend := v_pend || jsonb_build_object('contrato_id', r.id, 'codigo', r.codigo, 'negocio_id', r.negocio_id, 'motivo', res.pendencia);
    end if;
  end loop;
  insert into public.faturamento_execucoes (organizacao_id, origem, ate, gerados, pendencias)
  values (p_organizacao, p_origem, p_ate, v_total, v_pend) returning * into e;
  return e;
end;
$$;

-- RPC para a interface: organizações do usuário autenticado.
create or replace function public.gerar_faturamento_agora(p_ate date default current_date)
returns setof public.faturamento_execucoes
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid;
begin
  if p_ate > current_date + interval '2 months' then
    raise exception 'Data limite muito distante: no máximo 2 meses à frente.' using errcode = 'check_violation';
  end if;
  for v_org in select public.minhas_organizacoes() loop
    return next public.gerar_faturamento(v_org, p_ate, 'manual');
  end loop;
end;
$$;

-- Entrada do agendamento (pg_cron): todas as organizações, até hoje.
create or replace function public.gerar_faturamento_todas()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid;
begin
  for v_org in select id from public.organizacoes loop
    perform public.gerar_faturamento(v_org, current_date, 'agendado');
  end loop;
end;
$$;

-- View: faturamentos com status do lançamento
create view public.vw_faturamentos
with (security_invoker = true) as
select f.id, f.organizacao_id, f.contrato_id, f.competencia, f.lancamento_id, f.gerado_em,
       l.status as status_lancamento, l.valor, l.data_vencimento, l.data_efetivacao, l.descricao
from public.faturamentos f
join public.lancamentos l on l.id = f.lancamento_id;

-- -----------------------------------------------------------------------------
-- Privilégios e RLS
-- -----------------------------------------------------------------------------
revoke all on public.faturamentos from anon, authenticated;
revoke all on public.faturamento_execucoes from anon, authenticated;
grant select on public.faturamentos, public.faturamento_execucoes, public.vw_faturamentos to authenticated;
revoke all on function public.data_vencimento_no_mes(date, smallint) from public, anon;
revoke all on function public.competencias_pendentes(uuid, date) from public, anon, authenticated;
revoke all on function public.faturar_contrato(uuid, date) from public, anon, authenticated;
revoke all on function public.gerar_faturamento(uuid, date, text) from public, anon, authenticated;
revoke all on function public.gerar_faturamento_todas() from public, anon, authenticated;
revoke all on function public.gerar_faturamento_agora(date) from public, anon;
grant execute on function public.gerar_faturamento_agora(date) to authenticated;
revoke all on function public.tg_negocios_config() from public, anon, authenticated;
revoke all on function public.tg_contratos_config() from public, anon, authenticated;
revoke all on function public.tg_faturamentos_protecao() from public, anon, authenticated;

alter table public.faturamentos enable row level security;
alter table public.faturamento_execucoes enable row level security;
create policy faturamentos_select on public.faturamentos for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy faturamento_execucoes_select on public.faturamento_execucoes for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
