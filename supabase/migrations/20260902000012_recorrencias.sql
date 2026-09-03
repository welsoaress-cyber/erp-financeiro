-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0012: RECORRÊNCIAS EM LANÇAMENTOS (Etapa 8)
-- Um lançamento pode ser recorrente: ao ser efetivado, o motor gera a próxima
-- parcela (previsto) copiando os dados. A cadeia é rastreada por
-- lancamento_origem_id. Parar: número de parcelas, data de término ou
-- cancelamento/exclusão de uma parcela prevista (nada mais é gerado).
-- Independente do faturamento por contrato (Etapa 7).
-- =============================================================================

create type public.periodicidade_recorrencia as enum ('mensal', 'quinzenal', 'bimestral', 'trimestral', 'semestral', 'anual');

alter table public.lancamentos
  add column recorrente           boolean not null default false,
  add column periodicidade        public.periodicidade_recorrencia,
  add column numero_parcelas      integer check (numero_parcelas is null or numero_parcelas between 2 and 360),
  add column parcela_atual        integer check (parcela_atual is null or parcela_atual >= 1),
  add column data_fim_recorrencia date,
  add column lancamento_origem_id uuid references public.lancamentos (id) on delete restrict,
  -- avulso: nada de recorrência; recorrente: periodicidade + (parcelas ou término) + parcela válida
  add constraint lancamentos_recorrencia_check check (
    (not recorrente and periodicidade is null and numero_parcelas is null and parcela_atual is null
       and data_fim_recorrencia is null and lancamento_origem_id is null)
    or
    (recorrente and periodicidade is not null and parcela_atual >= 1
       and (numero_parcelas is not null or data_fim_recorrencia is not null)
       and (numero_parcelas is null or parcela_atual <= numero_parcelas))
  );
-- cada parcela gera no máximo uma próxima
create unique index lancamentos_origem_unico_idx on public.lancamentos (lancamento_origem_id) where lancamento_origem_id is not null;
comment on column public.lancamentos.recorrente is 'Ao efetivar, o motor gera a próxima parcela (previsto).';
comment on column public.lancamentos.lancamento_origem_id is 'Parcela anterior da cadeia (nulo = primeira).';

-- -----------------------------------------------------------------------------
-- Próxima data: mensal/bimestral/trimestral/semestral/anual mantêm o dia da
-- primeira parcela (ajustado ao fim do mês); quinzenal = +15 dias.
-- -----------------------------------------------------------------------------
create or replace function public.proxima_data_recorrencia(p_data date, p_periodicidade public.periodicidade_recorrencia, p_dia_base int)
returns date
language sql
immutable
set search_path = public
as $$
  select case p_periodicidade
    when 'quinzenal' then p_data + 15
    else (
      with m as (
        select (date_trunc('month', p_data) + (case p_periodicidade
          when 'mensal' then 1 when 'bimestral' then 2 when 'trimestral' then 3 when 'semestral' then 6 else 12 end) * interval '1 month')::date as ini
      )
      select ini + least(greatest(p_dia_base, 1), extract(day from (ini + interval '1 month' - interval '1 day'))::int) - 1 from m
    )
  end;
$$;

-- -----------------------------------------------------------------------------
-- Proteção: regras de imutabilidade da recorrência
-- -----------------------------------------------------------------------------
create or replace function public.tg_lancamentos_recorrencia()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_tem_filha boolean;
  o public.lancamentos%rowtype;
begin
  if new.recorrente then
    if new.origem = 'faturamento' then
      raise exception 'Cobrança gerada por contrato não pode ser recorrente: o faturamento já é automático.' using errcode = 'check_violation';
    end if;
    if new.data_fim_recorrencia is not null and new.data_fim_recorrencia < new.data_vencimento then
      raise exception 'A data de término da recorrência deve ser igual ou posterior ao vencimento.' using errcode = 'check_violation';
    end if;
  end if;

  if tg_op = 'INSERT' then
    if new.lancamento_origem_id is not null then
      select * into o from public.lancamentos where id = new.lancamento_origem_id;
      if not found or o.organizacao_id <> new.organizacao_id or not o.recorrente then
        raise exception 'Lançamento de origem inválido.' using errcode = 'check_violation';
      end if;
      if new.parcela_atual <> o.parcela_atual + 1 then
        raise exception 'Parcela fora de sequência.' using errcode = 'check_violation';
      end if;
    elsif new.recorrente and new.parcela_atual <> 1 then
      raise exception 'A primeira parcela deve ser a de número 1.' using errcode = 'check_violation';
    end if;
    return new;
  end if;

  -- UPDATE
  if new.lancamento_origem_id is distinct from old.lancamento_origem_id then
    raise exception 'A origem da parcela não pode ser alterada.' using errcode = 'check_violation';
  end if;
  v_tem_filha := exists (select 1 from public.lancamentos f where f.lancamento_origem_id = old.id);
  if old.recorrente and (v_tem_filha or old.parcela_atual > 1) then
    if new.recorrente is distinct from old.recorrente or new.periodicidade is distinct from old.periodicidade
       or new.numero_parcelas is distinct from old.numero_parcelas or new.data_fim_recorrencia is distinct from old.data_fim_recorrencia
       or new.parcela_atual is distinct from old.parcela_atual then
      raise exception 'A recorrência não pode ser alterada: já existem parcelas geradas.' using errcode = 'check_violation';
    end if;
  end if;
  if old.recorrente and v_tem_filha then
    if new.valor <> old.valor or new.data_competencia <> old.data_competencia or new.data_vencimento <> old.data_vencimento
       or new.conta_id <> old.conta_id or new.conta_destino_id is distinct from old.conta_destino_id
       or new.categoria_id is distinct from old.categoria_id or new.negocio_id is distinct from old.negocio_id
       or new.pessoa_id is distinct from old.pessoa_id or new.contrato_id is distinct from old.contrato_id then
      raise exception 'Lançamento com parcelas geradas: só descrição e observação podem ser alteradas.' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;
-- roda depois de lancamentos_a_contrato e antes de lancamentos_protecao (ordem alfabética)
create trigger lancamentos_b_recorrencia before insert or update on public.lancamentos for each row execute function public.tg_lancamentos_recorrencia();

-- -----------------------------------------------------------------------------
-- Motor: gerar a próxima parcela de um lançamento recorrente efetivado
-- (interno; chamado por criar/atualizar/efetivar dentro da sessão do motor)
-- -----------------------------------------------------------------------------
create or replace function public.gerar_proxima_parcela(p_id uuid)
returns public.lancamentos
language plpgsql
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  n public.lancamentos%rowtype;
  v_raiz_venc date;
  v_venc date;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found or not l.recorrente or l.status <> 'efetivado' then return null; end if;
  if exists (select 1 from public.lancamentos f where f.lancamento_origem_id = l.id) then return null; end if;
  if l.numero_parcelas is not null and l.parcela_atual >= l.numero_parcelas then return null; end if;

  -- dia-base = dia de vencimento da primeira parcela da cadeia (evita "escorregar" em meses curtos)
  with recursive cadeia as (
    select id, lancamento_origem_id, data_vencimento from public.lancamentos where id = l.id
    union all
    select p.id, p.lancamento_origem_id, p.data_vencimento from public.lancamentos p join cadeia c on p.id = c.lancamento_origem_id
  )
  select data_vencimento into v_raiz_venc from cadeia where lancamento_origem_id is null;

  v_venc := public.proxima_data_recorrencia(l.data_vencimento, l.periodicidade, extract(day from coalesce(v_raiz_venc, l.data_vencimento))::int);
  if l.data_fim_recorrencia is not null and v_venc > l.data_fim_recorrencia then return null; end if;

  insert into public.lancamentos (
    organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
    conta_id, conta_destino_id, categoria_id, observacao, origem, negocio_id, pessoa_id, contrato_id,
    recorrente, periodicidade, numero_parcelas, parcela_atual, data_fim_recorrencia, lancamento_origem_id
  ) values (
    l.organizacao_id, l.tipo, l.descricao, l.valor, v_venc - (l.data_vencimento - l.data_competencia), v_venc, null, 'previsto',
    l.conta_id, l.conta_destino_id, l.categoria_id, l.observacao, l.origem, l.negocio_id, l.pessoa_id, l.contrato_id,
    true, l.periodicidade, l.numero_parcelas, l.parcela_atual + 1, l.data_fim_recorrencia, l.id
  ) returning * into n;
  return n;
end;
$$;

-- -----------------------------------------------------------------------------
-- Motor público: criar / atualizar / efetivar com recorrência
-- -----------------------------------------------------------------------------
drop function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid);
drop function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid);

create function public.criar_lancamento(
  p_tipo text, p_descricao text, p_valor numeric, p_data_competencia date,
  p_data_vencimento date default null, p_data_efetivacao date default null,
  p_conta_id uuid default null, p_conta_destino_id uuid default null,
  p_categoria_id uuid default null, p_observacao text default null,
  p_negocio_id uuid default null, p_pessoa_id uuid default null, p_contrato_id uuid default null,
  p_recorrente boolean default false, p_periodicidade text default null,
  p_numero_parcelas integer default null, p_data_fim_recorrencia date default null
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
    status, conta_id, conta_destino_id, categoria_id, observacao, negocio_id, pessoa_id, contrato_id,
    recorrente, periodicidade, numero_parcelas, parcela_atual, data_fim_recorrencia
  ) values (
    v_org, p_tipo::public.tipo_lancamento, btrim(p_descricao), p_valor, p_data_competencia,
    coalesce(p_data_vencimento, p_data_competencia), p_data_efetivacao,
    (case when p_data_efetivacao is null then 'previsto' else 'efetivado' end)::public.status_lancamento,
    p_conta_id, p_conta_destino_id, p_categoria_id, nullif(btrim(coalesce(p_observacao, '')), ''), p_negocio_id, p_pessoa_id, p_contrato_id,
    coalesce(p_recorrente, false),
    case when coalesce(p_recorrente, false) then p_periodicidade::public.periodicidade_recorrencia end,
    case when coalesce(p_recorrente, false) then p_numero_parcelas end,
    case when coalesce(p_recorrente, false) then 1 end,
    case when coalesce(p_recorrente, false) then p_data_fim_recorrencia end
  ) returning * into l;
  perform public.gerar_movimentos(l.id);
  perform public.gerar_proxima_parcela(l.id); -- criado já efetivado ⇒ próxima parcela na hora
  return l;
end;
$$;

create function public.atualizar_lancamento(
  p_id uuid, p_descricao text, p_valor numeric, p_data_competencia date,
  p_data_vencimento date default null, p_data_efetivacao date default null,
  p_conta_id uuid default null, p_conta_destino_id uuid default null,
  p_categoria_id uuid default null, p_observacao text default null,
  p_negocio_id uuid default null, p_pessoa_id uuid default null, p_contrato_id uuid default null,
  p_recorrente boolean default false, p_periodicidade text default null,
  p_numero_parcelas integer default null, p_data_fim_recorrencia date default null
)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  v_rec boolean := coalesce(p_recorrente, false);
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
    contrato_id      = p_contrato_id,
    recorrente           = v_rec,
    periodicidade        = case when v_rec then p_periodicidade::public.periodicidade_recorrencia end,
    numero_parcelas      = case when v_rec then p_numero_parcelas end,
    parcela_atual        = case when v_rec then coalesce(parcela_atual, 1) end,
    data_fim_recorrencia = case when v_rec then p_data_fim_recorrencia end
  where id = p_id
  returning * into l;
  perform public.gerar_movimentos(l.id);
  perform public.gerar_proxima_parcela(l.id);
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
  perform public.gerar_proxima_parcela(l.id);
  return l;
end;
$$;

revoke all on function public.proxima_data_recorrencia(date, public.periodicidade_recorrencia, int) from public, anon;
grant execute on function public.proxima_data_recorrencia(date, public.periodicidade_recorrencia, int) to authenticated;
revoke all on function public.tg_lancamentos_recorrencia() from public, anon, authenticated;
revoke all on function public.gerar_proxima_parcela(uuid) from public, anon, authenticated;
revoke all on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid, boolean, text, integer, date) from public, anon;
revoke all on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid, boolean, text, integer, date) from public, anon;
grant execute on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid, boolean, text, integer, date) to authenticated;
grant execute on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid, boolean, text, integer, date) to authenticated;
