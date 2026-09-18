-- =============================================================================
-- 0100 · Etapa 58A — Pontos por pontualidade (motor + saldo + relatório)
-- =============================================================================
-- Cliente que paga a fatura ANTES do vencimento ganha pontos: quanto mais cedo,
-- mais pontos, até um teto de 30. Vitrine de prêmios e resgate ficam pra 58B —
-- aqui só o motor que concede os pontos e o extrato pra conferir.
--
-- Regra (fechada com o proprietário):
--   pontos = min(30, dias_de_antecedência + 1)   -- pagar no vencimento já vale 1
--   pontos = 0 se pago depois do vencimento (inclui promessa/voto de confiança,
--            que por definição só existe pra fatura já vencida)
--   só quitação TOTAL de contrato de RECEITA principal (não SVA/adicional,
--   marcado por contratos.elegivel_pontos; baixa parcial nunca gera pontos —
--   ela não passa por efetivar_lancamento, então já fica de fora sozinha)
--   opt-in por negócio (notificacoes_config.pontos_ativo)
--   vale a partir de 01/10/2026, sem retroativo
--   ciclo 01/10 a 30/09; contrato encerrado no meio do ciclo perde o saldo
--   estorno do lançamento remove os pontos daquela fatura
--
-- O vencimento usado no cálculo é sempre o ORIGINAL da competência
-- (lancamentos.data_vencimento_original, fixado na criação, nunca muda) —
-- reagendar a fatura do mês não deixa o cliente "fingir" antecedência; um
-- reagendamento só vale pra fatura do mês seguinte (linha nova, vencimento
-- original próprio). Toda alteração de data_vencimento fica auditada em
-- lancamentos_vencimento_historico.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Vencimento original + histórico de alteração (auditoria geral, não só pontos)
-- -----------------------------------------------------------------------------
alter table public.lancamentos add column data_vencimento_original date;
update public.lancamentos set data_vencimento_original = data_vencimento where data_vencimento_original is null;
alter table public.lancamentos alter column data_vencimento_original set not null;
comment on column public.lancamentos.data_vencimento_original is 'Vencimento como a fatura nasceu, nunca muda depois — referência fixa pros pontos de pontualidade (etapa 58A).';

create table public.lancamentos_vencimento_historico (
  id                 uuid primary key default gen_random_uuid(),
  lancamento_id      uuid not null references public.lancamentos (id) on delete cascade,
  vencimento_anterior date not null,
  vencimento_novo    date not null,
  usuario_id         uuid,
  alterado_em        timestamptz not null default now()
);
create index lancamentos_vencimento_historico_idx on public.lancamentos_vencimento_historico (lancamento_id);
comment on table public.lancamentos_vencimento_historico is 'Auditoria: toda vez que o vencimento de um lançamento é reagendado, fica registrado aqui (quem, quando, de/pra qual data).';

alter table public.lancamentos_vencimento_historico enable row level security;
create policy lancamentos_vencimento_historico_org on public.lancamentos_vencimento_historico for select using (
  exists (select 1 from public.lancamentos l where l.id = lancamento_id and l.organizacao_id in (select public.minhas_organizacoes()))
);
revoke all on public.lancamentos_vencimento_historico from public, anon, authenticated;
grant select on public.lancamentos_vencimento_historico to authenticated;

create function public.tg_lancamentos_vencimento_original()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.data_vencimento_original is null then
      new.data_vencimento_original := new.data_vencimento;
    end if;
    return new;
  end if;
  -- UPDATE: o original nunca muda depois de criado
  new.data_vencimento_original := old.data_vencimento_original;
  if new.data_vencimento is distinct from old.data_vencimento then
    insert into public.lancamentos_vencimento_historico (lancamento_id, vencimento_anterior, vencimento_novo, usuario_id)
    values (old.id, old.data_vencimento, new.data_vencimento, auth.uid());
  end if;
  return new;
end;
$$;
create trigger lancamentos_vencimento_original before insert or update on public.lancamentos
  for each row execute function public.tg_lancamentos_vencimento_original();

-- -----------------------------------------------------------------------------
-- 2. Contrato elegível + opt-in do negócio + ciclo anual
-- -----------------------------------------------------------------------------
alter table public.contratos add column elegivel_pontos boolean not null default true;
comment on column public.contratos.elegivel_pontos is 'Desligue para contrato adicional/SVA que não deve pontuar — só o contrato principal do cliente gera pontos de pontualidade (etapa 58A).';

alter table public.notificacoes_config add column pontos_ativo boolean not null default false;
comment on column public.notificacoes_config.pontos_ativo is 'Opt-in do programa de pontos por pontualidade (etapa 58A). Desligar só para de gerar pontos novos — o saldo já existente continua resgatável.';

create function public.ciclo_pontos_inicio(p_data date default current_date)
returns date
language sql
immutable
set search_path = public
as $$
  select case when extract(month from p_data) >= 10
    then make_date(extract(year from p_data)::int, 10, 1)
    else make_date(extract(year from p_data)::int - 1, 10, 1)
  end
$$;
comment on function public.ciclo_pontos_inicio(date) is 'Início do ciclo anual do programa de pontos (01/10 a 30/09) que contém a data informada.';

-- -----------------------------------------------------------------------------
-- 3. Pontos concedidos (histórico imutável) + alerta de saldo perdido na exclusão
-- -----------------------------------------------------------------------------
create table public.pontos_pontualidade (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  pessoa_id      uuid not null references public.pessoas (id) on delete restrict,
  contrato_id    uuid not null references public.contratos (id) on delete restrict,
  lancamento_id  uuid not null unique references public.lancamentos (id) on delete restrict,
  ciclo_inicio   date not null,
  pontos         smallint not null check (pontos between 1 and 30),
  criado_em      timestamptz not null default now()
);
create index pontos_pontualidade_saldo_idx on public.pontos_pontualidade (pessoa_id, negocio_id, ciclo_inicio);
comment on table public.pontos_pontualidade is 'Um registro por fatura paga antes do vencimento (etapa 58A). Imutável; só some se o lançamento for estornado.';

alter table public.pontos_pontualidade enable row level security;
create policy pontos_pontualidade_org on public.pontos_pontualidade for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.pontos_pontualidade from public, anon, authenticated;
grant select on public.pontos_pontualidade to authenticated;

create view public.vw_saldo_pontos with (security_invoker = true) as
select pessoa_id, negocio_id, ciclo_inicio, sum(pontos)::int as saldo
  from public.pontos_pontualidade
 group by pessoa_id, negocio_id, ciclo_inicio;
grant select on public.vw_saldo_pontos to authenticated;
comment on view public.vw_saldo_pontos is 'Saldo de pontos por pessoa/negócio/ciclo. Sem resgate ainda (58B) — soma pura dos pontos concedidos.';

create table public.pontos_perdidos_exclusao (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  pessoa_id      uuid not null,
  pessoa_nome    text not null,
  saldo_perdido  int not null check (saldo_perdido > 0),
  excluido_em    timestamptz not null default now()
);
-- contrato encerrado no meio do ciclo: perde o saldo de pontos daquele negócio (fechado com o proprietário)
create function public.tg_contratos_pontos_encerrado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'encerrado' and old.status is distinct from 'encerrado' then
    -- sem resgate/ciclo fechado ainda (58B): o saldo de pontos do negócio é sempre do ciclo em curso
    delete from public.pontos_pontualidade
     where pessoa_id = new.pessoa_id and negocio_id = new.negocio_id;
  end if;
  return new;
end;
$$;
create trigger contratos_pontos_encerrado after update on public.contratos
  for each row execute function public.tg_contratos_pontos_encerrado();

comment on table public.pontos_perdidos_exclusao is 'Alerta: saldo de pontos perdido quando a pessoa foi excluída do cadastro (sem histórico) com pontos ainda não resgatados. Sem FK em pessoa_id de propósito — ela já não existe mais. Base pra relatório futuro.';

alter table public.pontos_perdidos_exclusao enable row level security;
create policy pontos_perdidos_exclusao_org on public.pontos_perdidos_exclusao for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.pontos_perdidos_exclusao from public, anon, authenticated;
grant select on public.pontos_perdidos_exclusao to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Motor: concede pontos ao efetivar (quitação total), remove no estorno,
--    alerta e libera saldo na exclusão de pessoa
-- -----------------------------------------------------------------------------
create or replace function public.efetivar_lancamento(p_id uuid, p_data_efetivacao date default current_date, p_encargos numeric default 0, p_conta_id uuid default null)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  n public.lancamentos%rowtype;
  v_valor_original numeric;
  v_obs_original text;
  v_conta_original uuid;
  v_contrato public.contratos%rowtype;
  v_pontos_ativo boolean;
  v_dias int;
  v_pontos int;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.status <> 'previsto' then
    raise exception 'Somente lançamentos previstos podem ser efetivados.' using errcode = 'check_violation';
  end if;
  if p_encargos is null or p_encargos < 0 then
    raise exception 'Encargos não podem ser negativos.' using errcode = 'check_violation';
  end if;
  if p_conta_id is not null and p_conta_id <> l.conta_id then
    if l.tipo = 'transferencia' then
      raise exception 'Transferência não muda de conta na baixa.' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from public.contas c where c.id = p_conta_id and c.organizacao_id = l.organizacao_id) then
      raise exception 'Conta inválida para esta organização.' using errcode = 'check_violation';
    end if;
  end if;
  perform set_config('erp.motor', 'on', true);
  v_valor_original := l.valor;
  v_obs_original := l.observacao;
  v_conta_original := l.conta_id;
  if p_conta_id is not null and p_conta_id <> l.conta_id then
    perform set_config('erp.trocar_conta', 'on', true);
    update public.lancamentos set conta_id = p_conta_id where id = p_id;
  end if;
  if p_encargos > 0 then
    update public.lancamentos
       set valor = valor + round(p_encargos, 2),
           observacao = trim(both e'\n' from coalesce(observacao, '') || e'\n' ||
             'Encargos por atraso: R$ ' || replace(to_char(round(p_encargos, 2), 'FM999999990.00'), '.', ','))
     where id = p_id;
  end if;
  update public.lancamentos set status = 'efetivado', data_efetivacao = p_data_efetivacao where id = p_id returning * into l;
  perform public.gerar_movimentos(l.id);
  n := public.gerar_proxima_parcela(l.id);
  -- encargos e troca de conta são só desta parcela: a próxima (quando gerada aqui) volta ao original
  if n.id is not null then
    update public.lancamentos
       set valor = case when p_encargos > 0 then v_valor_original else valor end,
           observacao = case when p_encargos > 0 then v_obs_original else observacao end,
           conta_id = v_conta_original
     where id = n.id;
  end if;
  if p_data_efetivacao > l.data_vencimento then
    if l.recorrente then
      perform public.reancorar_recorrencia(l.id, p_data_efetivacao);
    elsif l.contrato_id is not null and l.origem = 'faturamento' then
      update public.contratos
         set dia_vencimento = least(extract(day from p_data_efetivacao)::int, 31)::smallint
       where id = l.contrato_id and status = 'ativo';
    end if;
  end if;

  -- pontos por pontualidade (58A): só quitação total de contrato de receita elegível,
  -- negócio com o programa ligado, e já dentro da vigência (01/10/2026 em diante)
  if l.tipo = 'receita' and l.contrato_id is not null and p_data_efetivacao >= date '2026-10-01' then
    select * into v_contrato from public.contratos where id = l.contrato_id;
    select coalesce(pontos_ativo, false) into v_pontos_ativo from public.notificacoes_config where negocio_id = l.negocio_id;
    if v_contrato.id is not null and v_contrato.tipo_financeiro = 'receita' and v_contrato.elegivel_pontos and v_pontos_ativo then
      v_dias := l.data_vencimento_original - p_data_efetivacao;
      if v_dias >= 0 then
        v_pontos := least(30, v_dias + 1);
        insert into public.pontos_pontualidade (organizacao_id, negocio_id, pessoa_id, contrato_id, lancamento_id, ciclo_inicio, pontos)
        values (l.organizacao_id, l.negocio_id, l.pessoa_id, l.contrato_id, l.id, public.ciclo_pontos_inicio(p_data_efetivacao), v_pontos);
      end if;
    end if;
  end if;

  return l;
end;
$$;

create or replace function public.estornar_lancamento(p_id uuid, p_motivo text)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare l public.lancamentos%rowtype; e public.lancamentos%rowtype;
begin
  select * into l from public.lancamentos where id = p_id for update;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.status <> 'efetivado' then
    raise exception 'Só lançamento efetivado pode ser estornado (previsto se cancela).' using errcode = 'check_violation';
  end if;
  if l.origem::text = 'estorno' then
    raise exception 'Estorno não se estorna — cancele o estorno se ele estiver errado.' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.lancamentos where estorno_de = l.id and status <> 'cancelado') then
    raise exception 'Este lançamento já foi estornado.' using errcode = 'check_violation';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Informe o motivo do estorno (mínimo 5 caracteres).' using errcode = 'check_violation';
  end if;

  perform set_config('erp.motor', 'on', true);
  insert into public.lancamentos (
    organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao,
    status, conta_id, conta_destino_id, categoria_id, observacao, origem,
    negocio_id, pessoa_id, contrato_id, estorno_de
  ) values (
    l.organizacao_id, l.tipo, left('Estorno: ' || l.descricao, 140), -l.valor, current_date, current_date, current_date,
    'efetivado', l.conta_id, l.conta_destino_id, l.categoria_id, 'Motivo do estorno: ' || btrim(p_motivo), 'estorno',
    l.negocio_id, l.pessoa_id, l.contrato_id, l.id
  ) returning * into e;
  perform public.gerar_movimentos(e.id);
  -- estornou o pagamento, estorna também os pontos de pontualidade daquela fatura (58A)
  delete from public.pontos_pontualidade where lancamento_id = l.id;
  return e;
end;
$$;

create or replace function public.excluir_pessoa(p_pessoa_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pessoa public.pessoas%rowtype;
  v_auth uuid[];
begin
  select * into v_pessoa from public.pessoas where id = p_pessoa_id;
  if not found then
    raise exception 'Pessoa não encontrada.' using errcode = 'no_data_found';
  end if;
  perform public.exigir_membro(v_pessoa.organizacao_id);

  -- vínculos de cadastro saem junto; histórico (FK) barra a exclusão
  select coalesce(array_agg(usuario_id), '{}') into v_auth
    from public.portal_acessos where pessoa_id = p_pessoa_id and usuario_id is not null;

  begin
    -- saldo de pontos de pontualidade não resgatado (58A): registra o alerta e libera a exclusão
    insert into public.pontos_perdidos_exclusao (organizacao_id, negocio_id, pessoa_id, pessoa_nome, saldo_perdido)
    select v_pessoa.organizacao_id, pp.negocio_id, p_pessoa_id, v_pessoa.nome, sum(pp.pontos)
      from public.pontos_pontualidade pp
     where pp.pessoa_id = p_pessoa_id
     group by pp.negocio_id
    having sum(pp.pontos) > 0;
    delete from public.pontos_pontualidade where pessoa_id = p_pessoa_id;

    delete from public.portal_acessos where pessoa_id = p_pessoa_id;
    delete from public.pessoa_negocio_vinculos where pessoa_id = p_pessoa_id;
    delete from public.pessoas where id = p_pessoa_id;
  exception when foreign_key_violation then
    raise exception 'Esta pessoa tem histórico (contratos, lançamentos, OS, comodato…) e não pode ser excluída. Desative-a.' using errcode = 'check_violation';
  end;

  -- login do portal fica órfão sem a pessoa: remove também
  if array_length(v_auth, 1) > 0 then
    delete from auth.users where id = any(v_auth);
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. Relatório: extrato de pontos por cliente
-- -----------------------------------------------------------------------------
create view public.vw_rel_pontos_pontualidade with (security_invoker = true) as
select pp.id, pp.organizacao_id, pp.negocio_id, n.nome as negocio, p.nome as cliente,
       pp.pontos, pp.ciclo_inicio, pp.criado_em,
       l.descricao as fatura, l.data_vencimento_original as vencimento, l.data_efetivacao as pago_em
  from public.pontos_pontualidade pp
  join public.negocios n on n.id = pp.negocio_id
  join public.pessoas p on p.id = pp.pessoa_id
  join public.lancamentos l on l.id = pp.lancamento_id;
grant select on public.vw_rel_pontos_pontualidade to authenticated;
