-- =============================================================================
-- 0038 · Cartão de crédito (Etapa 25)
-- =============================================================================
-- O cartão É uma conta (tipo novo 'credito'): saldo_inicial = limite total e o
-- saldo derivado = limite disponível. Compra à vista = despesa efetivada na
-- conta-cartão (consome limite). Parcelado = motor de parcelamento existente
-- (parcelas previstas; viram efetivadas no fechamento da fatura em que caem).
-- Pagamento = transferência real corrente → cartão (restaura o valor pago).
-- Fatura consolida as despesas efetivadas do período; itens em fatura_itens
-- (número/total de parcela já vivem em lancamentos — nada duplicado).
-- Sem juros/multa/rotativo nesta etapa.
-- =============================================================================

alter type public.tipo_conta add value if not exists 'credito';

create table public.cartoes_config (
  id              uuid primary key default gen_random_uuid(),
  organizacao_id  uuid not null references public.organizacoes (id) on delete restrict,
  conta_id        uuid not null unique references public.contas (id) on delete restrict,
  dia_fechamento  smallint not null check (dia_fechamento between 1 and 28),
  dia_vencimento  smallint not null check (dia_vencimento between 1 and 28),
  limite_total    numeric(14,2) not null check (limite_total >= 0),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
comment on table public.cartoes_config is 'Configuração de cartão de crédito por conta (tipo credito). limite_total é informativo; o disponível é o saldo derivado da conta.';

create type public.status_fatura as enum ('aberta', 'paga', 'vencida');

create table public.faturas (
  id              uuid primary key default gen_random_uuid(),
  organizacao_id  uuid not null references public.organizacoes (id) on delete restrict,
  conta_id        uuid not null references public.contas (id) on delete restrict,
  periodo_inicio  date not null,
  periodo_fim     date not null,
  data_vencimento date not null,
  valor_total     numeric(14,2) not null default 0 check (valor_total >= 0),
  valor_pago      numeric(14,2) not null default 0 check (valor_pago >= 0),
  status          public.status_fatura not null default 'aberta',
  data_pagamento  date,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  unique (conta_id, periodo_fim),
  check (periodo_fim >= periodo_inicio),
  check ((status = 'paga') = (data_pagamento is not null))
);

create table public.fatura_itens (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  fatura_id      uuid not null references public.faturas (id) on delete cascade,
  lancamento_id  uuid not null unique references public.lancamentos (id) on delete restrict,
  criado_em      timestamptz not null default now()
);
create index fatura_itens_fatura_idx on public.fatura_itens (fatura_id);

-- atualizado_em
create trigger cartoes_config_atualizado_em before update on public.cartoes_config for each row execute function public.tg_atualizado_em();
create trigger faturas_atualizado_em before update on public.faturas for each row execute function public.tg_atualizado_em();

-- config: só conta de crédito da mesma organização
create or replace function public.tg_cartoes_config()
returns trigger
language plpgsql
set search_path = public
as $$
declare c public.contas%rowtype;
begin
  select * into c from public.contas where id = new.conta_id;
  if not found or c.organizacao_id <> new.organizacao_id then
    raise exception 'Conta inválida.' using errcode = 'check_violation';
  end if;
  if c.tipo <> 'credito' then
    raise exception 'Cartão de crédito exige conta do tipo crédito.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger cartoes_config_b_valida before insert or update on public.cartoes_config for each row execute function public.tg_cartoes_config();

-- faturas e itens: só o motor grava
create or replace function public.tg_faturas_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not public.motor_ativo() then
    raise exception 'Faturas de cartão só são gravadas pelo motor.' using errcode = 'insufficient_privilege';
  end if;
  return coalesce(new, old);
end;
$$;
create trigger faturas_a_protecao before insert or update or delete on public.faturas for each row execute function public.tg_faturas_protecao();
create trigger fatura_itens_a_protecao before insert or update or delete on public.fatura_itens for each row execute function public.tg_faturas_protecao();

-- -----------------------------------------------------------------------------
-- Fechamento: consolida as despesas efetivadas da conta-cartão ainda sem fatura
-- e efetiva as parcelas previstas com vencimento até o fechamento (elas passam
-- a consumir limite aqui, como combinado). Idempotente por (conta, periodo_fim).
-- -----------------------------------------------------------------------------
create or replace function public.fechar_fatura_cartao(p_conta uuid, p_ref date default current_date)
returns public.faturas
language plpgsql
set search_path = public
as $$
declare
  cfg public.cartoes_config%rowtype;
  v_fech date; v_ini date; v_venc date;
  f public.faturas%rowtype;
  r record;
  v_total numeric(14,2);
begin
  select * into cfg from public.cartoes_config where conta_id = p_conta;
  if not found then return null; end if;
  -- último fechamento ocorrido até p_ref
  v_fech := public.data_vencimento_no_mes(date_trunc('month', p_ref)::date, cfg.dia_fechamento);
  if v_fech > p_ref then
    v_fech := public.data_vencimento_no_mes((date_trunc('month', p_ref) - interval '1 month')::date, cfg.dia_fechamento);
  end if;
  if exists (select 1 from public.faturas x where x.conta_id = p_conta and x.periodo_fim = v_fech) then
    select * into f from public.faturas x where x.conta_id = p_conta and x.periodo_fim = v_fech;
    return f;
  end if;
  v_ini := (public.data_vencimento_no_mes((v_fech - interval '1 month')::date, cfg.dia_fechamento) + 1)::date;
  v_venc := public.data_vencimento_no_mes(date_trunc('month', v_fech)::date, cfg.dia_vencimento);
  if v_venc <= v_fech then
    v_venc := public.data_vencimento_no_mes((date_trunc('month', v_fech) + interval '1 month')::date, cfg.dia_vencimento);
  end if;

  perform set_config('erp.motor', 'on', true);

  -- parcelas previstas que caem até este fechamento viram efetivadas (consomem limite)
  for r in
    select l.id, l.data_vencimento from public.lancamentos l
     where l.conta_id = p_conta and l.tipo = 'despesa' and l.status = 'previsto'
       and l.data_vencimento <= v_fech
     order by l.data_vencimento
  loop
    update public.lancamentos set status = 'efetivado', data_efetivacao = r.data_vencimento where id = r.id;
    perform public.gerar_movimentos(r.id);
    perform public.gerar_proxima_parcela(r.id);
  end loop;

  select coalesce(sum(l.valor), 0) into v_total
    from public.lancamentos l
   where l.conta_id = p_conta and l.tipo = 'despesa' and l.status = 'efetivado'
     and l.data_efetivacao <= v_fech
     and not exists (select 1 from public.fatura_itens i where i.lancamento_id = l.id);
  if v_total = 0 then return null; end if;

  insert into public.faturas (organizacao_id, conta_id, periodo_inicio, periodo_fim, data_vencimento, valor_total)
  values (cfg.organizacao_id, p_conta, v_ini, v_fech, v_venc, v_total)
  returning * into f;

  insert into public.fatura_itens (organizacao_id, fatura_id, lancamento_id)
  select cfg.organizacao_id, f.id, l.id
    from public.lancamentos l
   where l.conta_id = p_conta and l.tipo = 'despesa' and l.status = 'efetivado'
     and l.data_efetivacao <= v_fech
     and not exists (select 1 from public.fatura_itens i where i.lancamento_id = l.id);
  return f;
end;
$$;

-- Diário (cron): fecha o que estiver no dia e marca vencidas
create or replace function public.fechar_faturas_cartoes()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r record;
begin
  for r in select conta_id from public.cartoes_config loop
    perform public.fechar_fatura_cartao(r.conta_id, current_date);
  end loop;
  perform set_config('erp.motor', 'on', true);
  update public.faturas set status = 'vencida'
   where status = 'aberta' and data_vencimento < current_date;
end;
$$;

-- Botão da tela (e testes): fecha as faturas das organizações do usuário
create or replace function public.fechar_faturas_agora()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r record;
begin
  for r in
    select c.conta_id from public.cartoes_config c
     where c.organizacao_id in (select public.minhas_organizacoes())
  loop
    perform public.fechar_fatura_cartao(r.conta_id, current_date);
  end loop;
  perform set_config('erp.motor', 'on', true);
  update public.faturas set status = 'vencida'
   where status = 'aberta' and data_vencimento < current_date
     and organizacao_id in (select public.minhas_organizacoes());
end;
$$;

-- -----------------------------------------------------------------------------
-- Pagamento: transferência real (motor) da conta escolhida para a conta-cartão;
-- restaura o limite exatamente no valor pago. Aceita pagamento parcial.
-- -----------------------------------------------------------------------------
create or replace function public.pagar_fatura(
  p_fatura uuid, p_conta_origem uuid, p_valor numeric default null, p_data date default current_date
)
returns public.faturas
language plpgsql
security definer
set search_path = public
as $$
declare
  f public.faturas%rowtype;
  v_restante numeric(14,2);
  v_valor numeric(14,2);
begin
  select * into f from public.faturas where id = p_fatura;
  if not found then raise exception 'Fatura não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(f.organizacao_id);
  if f.status = 'paga' then raise exception 'Fatura já paga.' using errcode = 'check_violation'; end if;
  if p_conta_origem = f.conta_id then raise exception 'Pague a partir de outra conta.' using errcode = 'check_violation'; end if;
  if not exists (select 1 from public.contas c where c.id = p_conta_origem and c.organizacao_id = f.organizacao_id and c.ativo) then
    raise exception 'Conta de origem inválida.' using errcode = 'check_violation';
  end if;
  v_restante := f.valor_total - f.valor_pago;
  v_valor := coalesce(p_valor, v_restante);
  if v_valor <= 0 or v_valor > v_restante then
    raise exception 'Valor do pagamento deve ser maior que zero e no máximo o restante da fatura.' using errcode = 'check_violation';
  end if;

  perform public.criar_lancamento(
    'transferencia',
    'Pagamento fatura cartão · venc. ' || to_char(f.data_vencimento, 'DD/MM/YYYY'),
    v_valor, p_data, p_data, p_data,
    p_conta_origem, f.conta_id, null, null, null, null, null, false, null, null, null
  );

  perform set_config('erp.motor', 'on', true);
  update public.faturas
     set valor_pago = valor_pago + v_valor,
         status = case when valor_pago + v_valor >= valor_total then 'paga' else status end::public.status_fatura,
         data_pagamento = case when valor_pago + v_valor >= valor_total then p_data end
   where id = p_fatura
   returning * into f;
  return f;
end;
$$;

-- RLS e grants
alter table public.cartoes_config enable row level security;
alter table public.faturas enable row level security;
alter table public.fatura_itens enable row level security;
create policy cartoes_config_select on public.cartoes_config for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy cartoes_config_insert on public.cartoes_config for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy cartoes_config_update on public.cartoes_config for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy faturas_select on public.faturas for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy fatura_itens_select on public.fatura_itens for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.cartoes_config, public.faturas, public.fatura_itens from public, anon, authenticated;
grant select, insert, update on public.cartoes_config to authenticated;
grant select on public.faturas, public.fatura_itens to authenticated;

revoke all on function public.tg_cartoes_config(), public.tg_faturas_protecao() from public, anon, authenticated;
revoke all on function public.fechar_fatura_cartao(uuid, date) from public, anon, authenticated;
revoke all on function public.fechar_faturas_cartoes() from public, anon, authenticated;
revoke all on function public.fechar_faturas_agora() from public, anon;
grant execute on function public.fechar_faturas_agora() to authenticated;
revoke all on function public.pagar_fatura(uuid, uuid, numeric, date) from public, anon;
grant execute on function public.pagar_fatura(uuid, uuid, numeric, date) to authenticated;
