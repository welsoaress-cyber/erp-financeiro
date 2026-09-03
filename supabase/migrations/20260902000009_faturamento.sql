-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0009: FATURAMENTO RECORRENTE (Etapa 7)
-- Gera lançamentos PREVISTOS a partir de contratos ativos, uma vez por
-- competência, com registro em `faturamentos`. Execução manual (RPC) ou
-- agendada (migration 0010, pg_cron).
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
