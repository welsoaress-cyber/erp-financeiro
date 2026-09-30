-- Etapa 62 — Gestão de RH simplificada (funcionários, ponto informal, férias, folha manual).
-- Aprovado com o proprietário. Fora de escopo, permanentemente (risco trabalhista/legal real,
-- não é "depois"): cálculo de INSS/IRRF/FGTS/13º/rescisão, eSocial, ponto com valor jurídico
-- pleno (exige homologação REP-P, Portaria 671/MTE), banco de horas automático.
--
-- Arquitetura: funcionário NÃO duplica pessoas — é um vínculo de emprego sobre uma pessoa já
-- cadastrada, igual o padrão já usado em `tecnicos` (pessoa_id + negocio_id). Histórico de
-- cargo/salário não ganha tabela própria: qualquer update em `funcionarios` já cai na auditoria
-- genérica (tg_auditoria), reaproveitando o que existe (mesmo truque da etapa 61/leads). Folha
-- não é engine de cálculo: é um lançamento de despesa por funcionário por mês, valor final
-- informado manualmente, usando o motor de lançamentos que já existe — mesmo padrão de
-- aprovar_comissao_os (0055).

create type public.status_ferias as enum ('programada', 'em_gozo', 'concluida', 'cancelada');

create table public.funcionarios (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  pessoa_id      uuid not null references public.pessoas (id) on delete restrict,
  cargo          text check (cargo is null or char_length(cargo) <= 80),
  departamento   text check (departamento is null or char_length(departamento) <= 80),
  salario_base   numeric(14,2) not null default 0 check (salario_base >= 0),
  data_admissao  date not null default current_date,
  data_demissao  date,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (organizacao_id, pessoa_id),
  check (data_demissao is null or data_demissao >= data_admissao)
);
create index funcionarios_negocio_idx on public.funcionarios (negocio_id);
comment on table public.funcionarios is 'Vínculo de emprego sobre uma pessoa já cadastrada — não duplica nome/CPF (igual tecnicos, 0055). Ponto/férias/folha penduram aqui. Histórico de cargo/salário vem da auditoria genérica, não de tabela própria.';

create table public.funcionario_ponto (
  id            uuid primary key default gen_random_uuid(),
  funcionario_id uuid not null references public.funcionarios (id) on delete cascade,
  data          date not null,
  entrada       time,
  saida_almoco  time,
  volta_almoco  time,
  saida         time,
  observacao    text check (observacao is null or char_length(observacao) <= 300),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (funcionario_id, data)
);
comment on table public.funcionario_ponto is 'Ponto informal — controle interno de gestão, sem valor jurídico pleno (não é REP-P homologado).';

create table public.funcionario_ferias (
  id                        uuid primary key default gen_random_uuid(),
  funcionario_id            uuid not null references public.funcionarios (id) on delete cascade,
  periodo_aquisitivo_inicio date not null,
  periodo_aquisitivo_fim    date not null,
  data_inicio               date,
  data_fim                  date,
  status                    public.status_ferias not null default 'programada',
  observacao                text check (observacao is null or char_length(observacao) <= 300),
  criado_em                 timestamptz not null default now(),
  atualizado_em             timestamptz not null default now(),
  check (periodo_aquisitivo_fim > periodo_aquisitivo_inicio),
  check (data_fim is null or data_inicio is null or data_fim >= data_inicio)
);
comment on table public.funcionario_ferias is 'Tracker de datas de férias — sem cálculo de 1/3 constitucional nem abono pecuniário (isso é folha/contador, fora deste sistema).';

create table public.funcionario_folha (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  funcionario_id uuid not null references public.funcionarios (id) on delete restrict,
  mes            date not null,
  valor          numeric(14,2) not null check (valor > 0),
  lancamento_id  uuid not null references public.lancamentos (id) on delete restrict,
  observacao     text check (observacao is null or char_length(observacao) <= 300),
  criado_em      timestamptz not null default now(),
  unique (funcionario_id, mes),
  check (date_trunc('month', mes)::date = mes)
);
comment on table public.funcionario_folha is 'Um lançamento de despesa por funcionário por mês — valor final informado manualmente (salário+comissões-descontos já calculados fora do ERP, pelo contador). Sem engine de cálculo trabalhista. Imutável: estornar o lançamento em vez de editar.';

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------
create trigger funcionarios_atualizado before update on public.funcionarios for each row execute function public.tg_atualizado_em();
create trigger funcionarios_auditoria after insert or update or delete on public.funcionarios for each row execute function public.tg_auditoria();
create trigger funcionario_ponto_atualizado before update on public.funcionario_ponto for each row execute function public.tg_atualizado_em();
create trigger funcionario_ferias_atualizado before update on public.funcionario_ferias for each row execute function public.tg_atualizado_em();

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.funcionarios enable row level security;
alter table public.funcionario_ponto enable row level security;
alter table public.funcionario_ferias enable row level security;
alter table public.funcionario_folha enable row level security;

create policy funcionarios_org on public.funcionarios
  using (organizacao_id in (select public.minhas_organizacoes()))
  with check (organizacao_id in (select public.minhas_organizacoes()));

create policy funcionario_ponto_org on public.funcionario_ponto
  using (exists (select 1 from public.funcionarios f where f.id = funcionario_id and f.organizacao_id in (select public.minhas_organizacoes())))
  with check (exists (select 1 from public.funcionarios f where f.id = funcionario_id and f.organizacao_id in (select public.minhas_organizacoes())));

create policy funcionario_ferias_org on public.funcionario_ferias
  using (exists (select 1 from public.funcionarios f where f.id = funcionario_id and f.organizacao_id in (select public.minhas_organizacoes())))
  with check (exists (select 1 from public.funcionarios f where f.id = funcionario_id and f.organizacao_id in (select public.minhas_organizacoes())));

create policy funcionario_folha_org on public.funcionario_folha
  using (organizacao_id in (select public.minhas_organizacoes()));

revoke all on public.funcionarios, public.funcionario_ponto, public.funcionario_ferias, public.funcionario_folha from public, anon, authenticated;
grant select, insert, update on public.funcionarios to authenticated;
grant select, insert, update on public.funcionario_ponto to authenticated;
grant select, insert, update on public.funcionario_ferias to authenticated;
grant select on public.funcionario_folha to authenticated; -- só a função lancar_folha_funcionario grava (imutável)

-- -----------------------------------------------------------------------------
-- Folha: lançamento de despesa mensal por funcionário (valor final informado manualmente).
-- -----------------------------------------------------------------------------
create function public.lancar_folha_funcionario(p_funcionario_id uuid, p_mes date, p_valor numeric, p_conta_id uuid, p_vencimento date, p_centro_custo_id uuid default null, p_observacao text default null)
returns public.funcionario_folha
language plpgsql
security definer
set search_path = public
as $$
declare f public.funcionarios%rowtype; p public.pessoas%rowtype; v_mes date; v_cat uuid; l public.lancamentos%rowtype; ff public.funcionario_folha%rowtype;
begin
  select * into f from public.funcionarios where id = p_funcionario_id;
  if not found then raise exception 'Funcionário não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(f.organizacao_id);
  if p_valor is null or p_valor <= 0 then raise exception 'Informe o valor da folha.' using errcode = 'check_violation'; end if;
  v_mes := date_trunc('month', p_mes)::date;
  if exists (select 1 from public.funcionario_folha where funcionario_id = p_funcionario_id and mes = v_mes) then
    raise exception 'Já existe folha lançada para este funcionário neste mês.' using errcode = 'check_violation';
  end if;
  select * into p from public.pessoas where id = f.pessoa_id;

  select id into v_cat from public.categorias where organizacao_id = f.organizacao_id and tipo = 'despesa' and lower(nome) = 'folha de pagamento' limit 1;
  if v_cat is null then
    insert into public.categorias (organizacao_id, nome, tipo) values (f.organizacao_id, 'Folha de pagamento', 'despesa') returning id into v_cat;
  end if;

  l := public.criar_lancamento('despesa', 'Folha ' || to_char(v_mes, 'MM/YYYY') || ' — ' || p.nome, p_valor, p_vencimento, p_vencimento, null,
                               p_conta_id, null, v_cat, coalesce(nullif(btrim(p_observacao), ''), 'Folha de pagamento'),
                               f.negocio_id, f.pessoa_id, null, false, null, null, null);
  if p_centro_custo_id is not null then
    perform public.definir_centro_custo_lancamento(l.id, p_centro_custo_id);
  end if;

  insert into public.funcionario_folha (organizacao_id, funcionario_id, mes, valor, lancamento_id, observacao)
  values (f.organizacao_id, f.id, v_mes, p_valor, l.id, nullif(btrim(coalesce(p_observacao, '')), ''))
  returning * into ff;
  return ff;
end;
$$;
revoke all on function public.lancar_folha_funcionario(uuid, date, numeric, uuid, date, uuid, text) from public, anon;
grant execute on function public.lancar_folha_funcionario(uuid, date, numeric, uuid, date, uuid, text) to authenticated;
