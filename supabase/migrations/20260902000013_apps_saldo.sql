-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0013: SALDO PARA ATIVAÇÃO DE APPS (Etapa 9)
-- Um negócio pode operar uma carteira (dinheiro OU créditos) usada para ativar
-- apps para clientes. Tudo se apoia no que já existe:
--   negócio (dono da carteira) · pessoa (cliente) · plano (= app, preço da anuidade)
--   contrato (ativação, anual) · lançamentos (transferência da recarga, receita da
--   anuidade via faturamento, despesa do consumo) · contas (onde o dinheiro da
--   carteira fica) · categorias (despesa do consumo, receita do negócio).
-- Novo: carteira, transacoes_carteira, apps_catalogo, colunas em negocios.
-- =============================================================================

create type public.tipo_saldo_app          as enum ('dinheiro', 'credito');
create type public.tipo_transacao_carteira as enum ('recarga', 'consumo');

alter table public.negocios
  add column tipo_saldo     public.tipo_saldo_app,
  add column taxa_conversao numeric(10,4) check (taxa_conversao is null or taxa_conversao > 0),
  add constraint negocios_tipo_saldo_taxa_check check (tipo_saldo is distinct from 'credito' or taxa_conversao is not null);
comment on column public.negocios.tipo_saldo is 'Carteira de ativação: dinheiro (R$) ou credito. Nulo = negócio sem carteira.';
comment on column public.negocios.taxa_conversao is 'Créditos por R$ 1,00 (ex.: 0,1 = 1 crédito custa R$ 10). Só no modo crédito.';

-- Carteira: uma por negócio. Saldo mantido pelo motor a partir das transações.
create table public.carteira (
  id                   uuid primary key default gen_random_uuid(),
  organizacao_id       uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id           uuid not null unique references public.negocios (id) on delete restrict,
  conta_id             uuid not null references public.contas (id) on delete restrict,
  categoria_consumo_id uuid not null references public.categorias (id) on delete restrict,
  saldo                numeric(15,2) not null default 0 check (saldo >= 0),
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now()
);
comment on table public.carteira is 'Saldo de ativação de um negócio (R$ ou créditos). conta_id = conta onde o dinheiro fica; categoria_consumo_id = despesa do consumo.';

-- Catálogo de apps: cada app é um plano do negócio (preço da anuidade) + custo em saldo.
create table public.apps_catalogo (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  plano_id       uuid not null unique references public.planos (id) on delete restrict,
  nome           text not null check (char_length(btrim(nome)) between 1 and 80),
  custo          numeric(15,2) not null default 0 check (custo >= 0),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create unique index apps_catalogo_nome_unico_idx on public.apps_catalogo (negocio_id, lower(btrim(nome)));
comment on table public.apps_catalogo is 'Apps ativáveis de um negócio. custo = quanto consome da carteira (R$ ou créditos). plano_id = plano da anuidade.';

-- Transações da carteira: só inserção pelo motor; nunca alteradas ou excluídas.
create table public.transacoes_carteira (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  tipo           public.tipo_transacao_carteira not null,
  valor          numeric(15,2) not null check (valor > 0),
  valor_reais    numeric(14,2) not null check (valor_reais >= 0),
  app_id         uuid references public.apps_catalogo (id) on delete restrict,
  contrato_id    uuid references public.contratos (id) on delete restrict,
  lancamento_id  uuid references public.lancamentos (id) on delete restrict,
  data           date not null default current_date,
  observacao     text check (observacao is null or char_length(observacao) <= 300),
  criado_em      timestamptz not null default now(),
  check ((tipo = 'consumo') = (app_id is not null and contrato_id is not null))
);
create index transacoes_carteira_negocio_idx on public.transacoes_carteira (negocio_id, data desc);
comment on table public.transacoes_carteira is 'Histórico imutável da carteira. valor em unidades da carteira; valor_reais = contrapartida financeira.';

-- -----------------------------------------------------------------------------
-- Proteções
-- -----------------------------------------------------------------------------
create or replace function public.tg_carteira_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
declare c public.contas%rowtype; k public.categorias%rowtype;
begin
  if not public.motor_ativo() then
    raise exception 'A carteira só pode ser gravada pelo motor.' using errcode = 'insufficient_privilege';
  end if;
  if tg_op = 'UPDATE' and (new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id) then
    raise exception 'A carteira não pode mudar de negócio.' using errcode = 'check_violation';
  end if;
  perform public.validar_negocio(new.negocio_id, new.organizacao_id, tg_op = 'INSERT');
  select * into c from public.contas where id = new.conta_id;
  if not found or c.organizacao_id <> new.organizacao_id then raise exception 'Conta da carteira inválida.' using errcode = 'check_violation'; end if;
  if not c.ativo and (tg_op = 'INSERT' or new.conta_id <> old.conta_id) then raise exception 'A conta da carteira está inativa.' using errcode = 'check_violation'; end if;
  select * into k from public.categorias where id = new.categoria_consumo_id;
  if not found or k.organizacao_id <> new.organizacao_id then raise exception 'Categoria de consumo inválida.' using errcode = 'check_violation'; end if;
  if k.tipo <> 'despesa' then raise exception 'A categoria de consumo deve ser de despesa.' using errcode = 'check_violation'; end if;
  if not k.ativo and (tg_op = 'INSERT' or new.categoria_consumo_id <> old.categoria_consumo_id) then raise exception 'A categoria de consumo está inativa.' using errcode = 'check_violation'; end if;
  return new;
end;
$$;
create trigger carteira_protecao before insert or update on public.carteira for each row execute function public.tg_carteira_protecao();
create trigger carteira_atualizado_em before update on public.carteira for each row execute function public.tg_atualizado_em();
create trigger carteira_auditoria after insert or update or delete on public.carteira for each row execute function public.tg_auditoria();

create or replace function public.tg_apps_catalogo_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
declare pl public.planos%rowtype;
begin
  new.nome := btrim(new.nome);
  if tg_op = 'INSERT' then
    if not public.motor_ativo() then
      raise exception 'Apps são criados pela função criar_app.' using errcode = 'insufficient_privilege';
    end if;
    select * into pl from public.planos where id = new.plano_id;
    if not found or pl.negocio_id <> new.negocio_id or pl.organizacao_id <> new.organizacao_id then
      raise exception 'Plano do app inválido.' using errcode = 'check_violation';
    end if;
    return new;
  end if;
  if new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id or new.plano_id <> old.plano_id then
    raise exception 'O app não pode mudar de negócio ou plano.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
-- nome/ativo do app refletem no plano (catálogo único)
create or replace function public.tg_apps_catalogo_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.nome <> old.nome or new.ativo <> old.ativo then
    update public.planos set nome = new.nome, ativo = new.ativo where id = new.plano_id;
  end if;
  return new;
end;
$$;
create trigger apps_catalogo_protecao before insert or update on public.apps_catalogo for each row execute function public.tg_apps_catalogo_protecao();
create trigger apps_catalogo_sync after update on public.apps_catalogo for each row execute function public.tg_apps_catalogo_sync();
create trigger apps_catalogo_atualizado_em before update on public.apps_catalogo for each row execute function public.tg_atualizado_em();
create trigger apps_catalogo_auditoria after insert or update or delete on public.apps_catalogo for each row execute function public.tg_auditoria();

-- Transações: só o motor insere; nunca update/delete; saldo da carteira acompanha
create or replace function public.tg_transacoes_carteira_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception 'Transações da carteira não podem ser alteradas nem excluídas.' using errcode = 'check_violation';
  end if;
  if not public.motor_ativo() then
    raise exception 'Transações da carteira só são gravadas pelo motor.' using errcode = 'insufficient_privilege';
  end if;
  new.observacao := nullif(btrim(coalesce(new.observacao, '')), '');
  return new;
end;
$$;
create or replace function public.tg_transacoes_carteira_saldo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  update public.carteira
     set saldo = saldo + (case when new.tipo = 'recarga' then new.valor else -new.valor end)
   where negocio_id = new.negocio_id;
  if not found then
    raise exception 'Negócio sem carteira configurada.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger transacoes_carteira_protecao before insert or update or delete on public.transacoes_carteira for each row execute function public.tg_transacoes_carteira_protecao();
create trigger transacoes_carteira_saldo after insert on public.transacoes_carteira for each row execute function public.tg_transacoes_carteira_saldo();
create trigger transacoes_carteira_auditoria after insert or update or delete on public.transacoes_carteira for each row execute function public.tg_auditoria();

-- -----------------------------------------------------------------------------
-- Motor da carteira (security definer; membro da organização obrigatório)
-- -----------------------------------------------------------------------------
create or replace function public.configurar_carteira(p_negocio_id uuid, p_conta_id uuid, p_categoria_consumo_id uuid)
returns public.carteira
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; w public.carteira%rowtype;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio inválido.' using errcode = 'check_violation'; end if;
  perform public.exigir_membro(n.organizacao_id);
  if n.tipo_saldo is null then raise exception 'Defina o tipo de saldo do negócio (dinheiro ou crédito) antes de configurar a carteira.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  insert into public.carteira (organizacao_id, negocio_id, conta_id, categoria_consumo_id)
  values (n.organizacao_id, p_negocio_id, p_conta_id, p_categoria_consumo_id)
  on conflict (negocio_id) do update set conta_id = excluded.conta_id, categoria_consumo_id = excluded.categoria_consumo_id
  returning * into w;
  return w;
end;
$$;

create or replace function public.criar_app(p_negocio_id uuid, p_nome text, p_custo numeric, p_anuidade numeric)
returns public.apps_catalogo
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; pl public.planos%rowtype; a public.apps_catalogo%rowtype;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio inválido.' using errcode = 'check_violation'; end if;
  perform public.exigir_membro(n.organizacao_id);
  if n.tipo_saldo is null then raise exception 'Este negócio não opera carteira de ativação.' using errcode = 'check_violation'; end if;
  if p_anuidade is null or p_anuidade < 0 then raise exception 'Informe o valor da anuidade.' using errcode = 'check_violation'; end if;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade, descricao)
  values (n.organizacao_id, p_negocio_id, btrim(p_nome), p_anuidade, 'anual', 'Anuidade do app')
  returning * into pl;
  perform set_config('erp.motor', 'on', true);
  insert into public.apps_catalogo (organizacao_id, negocio_id, plano_id, nome, custo)
  values (n.organizacao_id, p_negocio_id, pl.id, btrim(p_nome), coalesce(p_custo, 0))
  returning * into a;
  return a;
end;
$$;

-- Recarga: entra na carteira (R$ ou créditos) e move o dinheiro da conta de origem para a conta da carteira.
create or replace function public.recarregar_carteira(p_negocio_id uuid, p_valor_reais numeric, p_conta_origem_id uuid, p_data date default current_date, p_observacao text default null)
returns public.transacoes_carteira
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; w public.carteira%rowtype; l public.lancamentos%rowtype; t public.transacoes_carteira%rowtype; v_unidades numeric(15,2);
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio inválido.' using errcode = 'check_violation'; end if;
  perform public.exigir_membro(n.organizacao_id);
  select * into w from public.carteira where negocio_id = p_negocio_id for update;
  if not found then raise exception 'Configure a carteira do negócio (conta e categoria) antes de recarregar.' using errcode = 'check_violation'; end if;
  if p_valor_reais is null or p_valor_reais <= 0 then raise exception 'Informe um valor de recarga maior que zero.' using errcode = 'check_violation'; end if;
  if p_conta_origem_id is null or p_conta_origem_id = w.conta_id then raise exception 'Informe a conta de origem (diferente da conta da carteira).' using errcode = 'check_violation'; end if;
  v_unidades := case when n.tipo_saldo = 'credito' then round(p_valor_reais * n.taxa_conversao, 2) else p_valor_reais end;
  if v_unidades <= 0 then raise exception 'Valor não gera créditos com a taxa atual.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  insert into public.lancamentos (organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
                                  conta_id, conta_destino_id, origem, negocio_id, observacao)
  values (n.organizacao_id, 'transferencia', left('Recarga de saldo · ' || n.nome, 140), p_valor_reais, p_data, p_data, p_data, 'efetivado',
          p_conta_origem_id, w.conta_id, 'sistema', p_negocio_id, nullif(btrim(coalesce(p_observacao, '')), ''))
  returning * into l;
  perform public.gerar_movimentos(l.id);
  insert into public.transacoes_carteira (organizacao_id, negocio_id, tipo, valor, valor_reais, lancamento_id, data, observacao)
  values (n.organizacao_id, p_negocio_id, 'recarga', v_unidades, p_valor_reais, l.id, p_data, p_observacao)
  returning * into t;
  return t;
end;
$$;

-- Ativação: consome saldo, abre contrato anual (plano do app), fatura a anuidade (receita prevista) e lança a despesa do consumo.
create or replace function public.ativar_app(p_negocio_id uuid, p_pessoa_id uuid, p_app_id uuid, p_data date default current_date,
                                              p_anuidade numeric default null, p_dia_vencimento integer default null, p_observacao text default null)
returns public.contratos
language plpgsql
security definer
set search_path = public
as $$
declare
  n public.negocios%rowtype; w public.carteira%rowtype; a public.apps_catalogo%rowtype; pl public.planos%rowtype;
  c public.contratos%rowtype; l public.lancamentos%rowtype; v_reais numeric(14,2); v_fat record;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio inválido.' using errcode = 'check_violation'; end if;
  perform public.exigir_membro(n.organizacao_id);
  select * into a from public.apps_catalogo where id = p_app_id;
  if not found or a.negocio_id <> p_negocio_id then raise exception 'App inválido para este negócio.' using errcode = 'check_violation'; end if;
  if not a.ativo then raise exception 'O app está inativo.' using errcode = 'check_violation'; end if;
  select * into pl from public.planos where id = a.plano_id;
  select * into w from public.carteira where negocio_id = p_negocio_id for update;
  if not found then raise exception 'Configure a carteira do negócio antes de ativar apps.' using errcode = 'check_violation'; end if;
  if w.saldo < a.custo then
    raise exception 'Saldo insuficiente: disponível %, necessário %.', to_char(w.saldo, 'FM999G999G990D00'), to_char(a.custo, 'FM999G999G990D00') using errcode = 'check_violation';
  end if;

  -- contrato de anuidade (regras do contrato valem: pessoa ativa, plano ativo, código sequencial, vínculo cliente)
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento,
                                faturamento_automatico, faturar_desde, observacao)
  values (n.organizacao_id, p_negocio_id, p_pessoa_id, pl.id, coalesce(p_anuidade, pl.valor_tabela), 'anual', p_data,
          coalesce(p_dia_vencimento, extract(day from p_data)::int), true, p_data,
          left('Ativação do app ' || a.nome || coalesce('. ' || nullif(btrim(coalesce(p_observacao, '')), ''), ''), 500))
  returning * into c;

  -- receita da anuidade: mesmo motor do faturamento (registra em faturamentos, nunca duplica)
  select * into v_fat from public.faturar_contrato(c.id, p_data);
  if v_fat.pendencia is not null then
    raise exception 'Não foi possível faturar a anuidade: %', v_fat.pendencia using errcode = 'check_violation';
  end if;

  -- despesa do consumo (sai da conta da carteira, vinculada ao contrato/pessoa)
  v_reais := case when n.tipo_saldo = 'credito' then round(a.custo / n.taxa_conversao, 2) else a.custo end;
  perform set_config('erp.motor', 'on', true);
  if v_reais > 0 then
    insert into public.lancamentos (organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
                                    conta_id, categoria_id, origem, negocio_id, pessoa_id, contrato_id)
    values (n.organizacao_id, 'despesa', left('Ativação ' || a.nome || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140), v_reais, p_data, p_data, p_data, 'efetivado',
            w.conta_id, w.categoria_consumo_id, 'sistema', p_negocio_id, p_pessoa_id, c.id)
    returning * into l;
    perform public.gerar_movimentos(l.id);
  end if;
  if a.custo > 0 then
    insert into public.transacoes_carteira (organizacao_id, negocio_id, tipo, valor, valor_reais, app_id, contrato_id, lancamento_id, data, observacao)
    values (n.organizacao_id, p_negocio_id, 'consumo', a.custo, v_reais, a.id, c.id, l.id, p_data, p_observacao);
  end if;
  return c;
end;
$$;

-- -----------------------------------------------------------------------------
-- Views (RLS do chamador)
-- -----------------------------------------------------------------------------
create view public.vw_carteira_resumo
with (security_invoker = true) as
select n.id as negocio_id, n.organizacao_id, n.nome as negocio, n.tipo_saldo, n.taxa_conversao,
       w.id as carteira_id, w.conta_id, w.categoria_consumo_id, coalesce(w.saldo, 0) as saldo,
       coalesce((select sum(t.valor) from public.transacoes_carteira t where t.negocio_id = n.id and t.tipo = 'recarga'), 0) as total_recargas,
       coalesce((select sum(t.valor) from public.transacoes_carteira t where t.negocio_id = n.id and t.tipo = 'consumo'), 0) as total_consumos,
       (select count(*) from public.contratos c join public.apps_catalogo a on a.plano_id = c.plano_id where c.negocio_id = n.id and c.status = 'ativo') as apps_ativos,
       coalesce((select sum(c.valor) from public.contratos c join public.apps_catalogo a on a.plano_id = c.plano_id where c.negocio_id = n.id and c.status = 'ativo'), 0) as anuidades_ativas
  from public.negocios n
  left join public.carteira w on w.negocio_id = n.id
 where n.tipo_saldo is not null;

create view public.vw_contratos_app
with (security_invoker = true) as
select c.id as contrato_id, c.organizacao_id, c.negocio_id, a.id as app_id, a.nome as app, c.pessoa_id, c.codigo, c.valor as anuidade,
       c.data_inicio, c.data_fim, c.status,
       case when c.status = 'encerrado' then 'cancelado'
            when exists (select 1 from public.lancamentos l where l.contrato_id = c.id and l.status = 'previsto' and l.data_vencimento < current_date) then 'vencido'
            else 'ativo' end as situacao,
       (select min(l.data_vencimento) from public.lancamentos l where l.contrato_id = c.id and l.status = 'previsto') as proximo_vencimento
  from public.contratos c
  join public.apps_catalogo a on a.plano_id = c.plano_id;

-- -----------------------------------------------------------------------------
-- Permissões e RLS
-- -----------------------------------------------------------------------------
alter table public.carteira enable row level security;
alter table public.apps_catalogo enable row level security;
alter table public.transacoes_carteira enable row level security;
create policy carteira_select on public.carteira for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy apps_catalogo_select on public.apps_catalogo for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy apps_catalogo_update on public.apps_catalogo for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy transacoes_carteira_select on public.transacoes_carteira for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.carteira, public.apps_catalogo, public.transacoes_carteira from public, anon, authenticated;
grant select on public.carteira, public.transacoes_carteira to authenticated;
grant select, update on public.apps_catalogo to authenticated;
grant select on public.vw_carteira_resumo, public.vw_contratos_app to authenticated;
revoke all on function public.tg_carteira_protecao(), public.tg_apps_catalogo_protecao(), public.tg_apps_catalogo_sync(),
  public.tg_transacoes_carteira_protecao(), public.tg_transacoes_carteira_saldo() from public, anon, authenticated;
revoke all on function public.configurar_carteira(uuid, uuid, uuid), public.criar_app(uuid, text, numeric, numeric),
  public.recarregar_carteira(uuid, numeric, uuid, date, text), public.ativar_app(uuid, uuid, uuid, date, numeric, integer, text) from public, anon;
grant execute on function public.configurar_carteira(uuid, uuid, uuid), public.criar_app(uuid, text, numeric, numeric),
  public.recarregar_carteira(uuid, numeric, uuid, date, text), public.ativar_app(uuid, uuid, uuid, date, numeric, integer, text) to authenticated;
