-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0030: CARTEIRA COM DOIS SALDOS (Etapa 17)
-- A carteira de ativação de apps passa a manter DOIS saldos simultâneos por
-- negócio — dinheiro (R$) e créditos —, sem taxa de conversão fixa. Cada
-- recarga e cada ativação informa manualmente a forma de pagamento (dinheiro
-- ou crédito) e o valor, pois o preço em cada moeda varia por negociação com
-- a plataforma e não é mais um dado fixo do negócio nem do app do catálogo.
-- =============================================================================

-- Script idempotente e atômico: seguro rodar de novo mesmo que uma tentativa
-- anterior tenha parado no meio (ex.: coluna já criada, backfill pendente).
begin;

-- -----------------------------------------------------------------------------
-- 0. Views antigas dependem das colunas que vão mudar; recriadas no fim.
-- -----------------------------------------------------------------------------
drop view if exists public.vw_carteira_resumo;
drop view if exists public.vw_contratos_app;

-- -----------------------------------------------------------------------------
-- 1. Carteira: dois saldos em vez de um só. Backfill a partir do saldo antigo
--    e do modo (dinheiro/crédito) que o negócio operava. O backfill é um
--    UPDATE na carteira: precisa do motor ligado (trigger de proteção).
-- -----------------------------------------------------------------------------
alter table public.carteira
  add column if not exists saldo_dinheiro numeric(15,2),
  add column if not exists saldo_credito  numeric(15,2);

do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'negocios' and column_name = 'tipo_saldo') then
    perform set_config('erp.motor', 'on', true);
    update public.carteira w
       set saldo_dinheiro = coalesce(w.saldo_dinheiro, case when n.tipo_saldo = 'dinheiro' then w.saldo else 0 end),
           saldo_credito  = coalesce(w.saldo_credito,  case when n.tipo_saldo = 'credito'  then w.saldo else 0 end)
      from public.negocios n
     where n.id = w.negocio_id;
  end if;
end $$;
update public.carteira set saldo_dinheiro = 0 where saldo_dinheiro is null;
update public.carteira set saldo_credito = 0 where saldo_credito is null;

alter table public.carteira
  alter column saldo_dinheiro set not null,
  alter column saldo_dinheiro set default 0,
  alter column saldo_credito set not null,
  alter column saldo_credito set default 0;
alter table public.carteira drop constraint if exists carteira_saldo_dinheiro_check;
alter table public.carteira add constraint carteira_saldo_dinheiro_check check (saldo_dinheiro >= 0);
alter table public.carteira drop constraint if exists carteira_saldo_credito_check;
alter table public.carteira add constraint carteira_saldo_credito_check check (saldo_credito >= 0);
alter table public.carteira drop column if exists saldo;
comment on column public.carteira.saldo_dinheiro is 'Saldo em R$ disponível para ativar apps pagando com PIX/dinheiro.';
comment on column public.carteira.saldo_credito is 'Saldo em créditos da plataforma (sem taxa fixa; cada recarga informa quanto recebeu).';

-- -----------------------------------------------------------------------------
-- 2. Transações: cada uma informa a forma de pagamento (dinheiro/crédito).
--    valor_reais deixa de ser obrigatório (consumo em crédito não tem R$
--    associado — o custo real já foi pago na recarga que trouxe o crédito).
--    O backfill é um UPDATE: a trigger de proteção bloqueia QUALQUER update,
--    mesmo com o motor ligado — precisa ser desativada só para este passo.
-- -----------------------------------------------------------------------------
alter table public.transacoes_carteira add column if not exists forma_pagamento public.tipo_saldo_app;
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'negocios' and column_name = 'tipo_saldo') then
    alter table public.transacoes_carteira disable trigger transacoes_carteira_protecao;
    update public.transacoes_carteira t
       set forma_pagamento = coalesce(t.forma_pagamento, n.tipo_saldo, 'dinheiro')
      from public.negocios n
     where n.id = t.negocio_id;
    alter table public.transacoes_carteira enable trigger transacoes_carteira_protecao;
  end if;
end $$;
update public.transacoes_carteira set forma_pagamento = 'dinheiro' where forma_pagamento is null;

alter table public.transacoes_carteira
  alter column forma_pagamento set not null,
  alter column valor_reais drop not null;
alter table public.transacoes_carteira drop constraint if exists transacoes_carteira_valor_reais_dinheiro_check;
alter table public.transacoes_carteira add constraint transacoes_carteira_valor_reais_dinheiro_check check (forma_pagamento <> 'dinheiro' or valor_reais is not null);
alter table public.transacoes_carteira drop constraint if exists transacoes_carteira_valor_reais_recarga_check;
alter table public.transacoes_carteira add constraint transacoes_carteira_valor_reais_recarga_check check (tipo <> 'recarga' or valor_reais is not null);
comment on column public.transacoes_carteira.forma_pagamento is 'Saldo debitado/creditado por esta transação: dinheiro ou crédito.';
comment on column public.transacoes_carteira.valor is 'Valor em unidades da forma de pagamento: R$ se dinheiro, nº de créditos se crédito.';
comment on column public.transacoes_carteira.valor_reais is 'Contrapartida em R$ (PIX). Sempre presente em recarga e em consumo pago com dinheiro; nulo em consumo pago com crédito.';

-- -----------------------------------------------------------------------------
-- 3. Catálogo de apps: sem custo fixo (172 apps cujo preço varia). Cada
--    ativação informa o valor pago na hora.
-- -----------------------------------------------------------------------------
alter table public.apps_catalogo drop column if exists custo;

-- -----------------------------------------------------------------------------
-- 4. Negócios: troca o modo único (dinheiro OU crédito + taxa) por uma
--    simples habilitação do módulo — a carteira opera os dois saldos sempre.
-- -----------------------------------------------------------------------------
alter table public.negocios add column if not exists usa_carteira boolean;
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'negocios' and column_name = 'tipo_saldo') then
    update public.negocios set usa_carteira = coalesce(usa_carteira, tipo_saldo is not null);
  end if;
end $$;
update public.negocios set usa_carteira = false where usa_carteira is null;
alter table public.negocios
  alter column usa_carteira set not null,
  alter column usa_carteira set default false;
alter table public.negocios
  drop constraint if exists negocios_tipo_saldo_taxa_check,
  drop column if exists tipo_saldo,
  drop column if exists taxa_conversao;
comment on column public.negocios.usa_carteira is 'Habilita o módulo Apps (carteira dinheiro + crédito) para este negócio.';

-- -----------------------------------------------------------------------------
-- 5. Trigger de saldo: debita/credita o saldo (dinheiro ou crédito) conforme
--    a forma de pagamento da transação.
-- -----------------------------------------------------------------------------
create or replace function public.tg_transacoes_carteira_saldo()
returns trigger
language plpgsql
set search_path = public
as $$
declare v_delta numeric(15,2) := case when new.tipo = 'recarga' then new.valor else -new.valor end;
begin
  if new.forma_pagamento = 'dinheiro' then
    update public.carteira set saldo_dinheiro = saldo_dinheiro + v_delta where negocio_id = new.negocio_id;
  else
    update public.carteira set saldo_credito = saldo_credito + v_delta where negocio_id = new.negocio_id;
  end if;
  if not found then
    raise exception 'Negócio sem carteira configurada.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. Motor: assinaturas mudam (custo/taxa saem, forma de pagamento entra).
-- -----------------------------------------------------------------------------
drop function if exists public.criar_app(uuid, text, numeric, numeric);
drop function if exists public.recarregar_carteira(uuid, numeric, uuid, date, text);
drop function if exists public.ativar_app(uuid, uuid, uuid, date, numeric, integer, text);

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
  update public.negocios set usa_carteira = true where id = p_negocio_id;
  perform set_config('erp.motor', 'on', true);
  insert into public.carteira (organizacao_id, negocio_id, conta_id, categoria_consumo_id)
  values (n.organizacao_id, p_negocio_id, p_conta_id, p_categoria_consumo_id)
  on conflict (negocio_id) do update set conta_id = excluded.conta_id, categoria_consumo_id = excluded.categoria_consumo_id
  returning * into w;
  return w;
end;
$$;

create or replace function public.criar_app(p_negocio_id uuid, p_nome text, p_anuidade numeric)
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
  if not n.usa_carteira then raise exception 'Este negócio não opera carteira de ativação.' using errcode = 'check_violation'; end if;
  if p_anuidade is null or p_anuidade < 0 then raise exception 'Informe o valor da anuidade.' using errcode = 'check_violation'; end if;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade, descricao)
  values (n.organizacao_id, p_negocio_id, btrim(p_nome), p_anuidade, 'anual', 'Anuidade do app')
  returning * into pl;
  perform set_config('erp.motor', 'on', true);
  insert into public.apps_catalogo (organizacao_id, negocio_id, plano_id, nome)
  values (n.organizacao_id, p_negocio_id, pl.id, btrim(p_nome))
  returning * into a;
  return a;
end;
$$;

-- Recarga: sempre um PIX real (valor_reais); unidades creditadas na carteira
-- variam pela forma — em dinheiro é o próprio PIX, em crédito é o que a
-- plataforma informou ter creditado (sem taxa fixa).
create or replace function public.recarregar_carteira(p_negocio_id uuid, p_forma_pagamento public.tipo_saldo_app, p_valor_reais numeric,
                                                        p_unidades numeric default null, p_conta_origem_id uuid default null,
                                                        p_data date default current_date, p_observacao text default null)
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
  if p_valor_reais is null or p_valor_reais <= 0 then raise exception 'Informe o valor pago (PIX) maior que zero.' using errcode = 'check_violation'; end if;
  if p_conta_origem_id is null or p_conta_origem_id = w.conta_id then raise exception 'Informe a conta de origem (diferente da conta da carteira).' using errcode = 'check_violation'; end if;
  v_unidades := case when p_forma_pagamento = 'credito' then p_unidades else p_valor_reais end;
  if v_unidades is null or v_unidades <= 0 then raise exception 'Informe quantos créditos a recarga trouxe.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  insert into public.lancamentos (organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
                                  conta_id, conta_destino_id, origem, negocio_id, observacao)
  values (n.organizacao_id, 'transferencia', left('Recarga de saldo · ' || n.nome, 140), p_valor_reais, p_data, p_data, p_data, 'efetivado',
          p_conta_origem_id, w.conta_id, 'sistema', p_negocio_id, nullif(btrim(coalesce(p_observacao, '')), ''))
  returning * into l;
  perform public.gerar_movimentos(l.id);
  insert into public.transacoes_carteira (organizacao_id, negocio_id, tipo, forma_pagamento, valor, valor_reais, lancamento_id, data, observacao)
  values (n.organizacao_id, p_negocio_id, 'recarga', p_forma_pagamento, v_unidades, p_valor_reais, l.id, p_data, p_observacao)
  returning * into t;
  return t;
end;
$$;

-- Ativação: o valor pago é informado na hora (não há preço fixo no catálogo).
-- Em dinheiro, o valor também vira a despesa do consumo (R$ sai da carteira).
-- Em crédito, só debita o saldo de créditos — sem lançamento de despesa (o
-- custo em R$ já foi reconhecido na recarga que trouxe esses créditos).
create or replace function public.ativar_app(p_negocio_id uuid, p_pessoa_id uuid, p_app_id uuid, p_forma_pagamento public.tipo_saldo_app, p_valor numeric,
                                              p_data date default current_date, p_anuidade numeric default null, p_dia_vencimento integer default null,
                                              p_observacao text default null)
returns public.contratos
language plpgsql
security definer
set search_path = public
as $$
declare
  n public.negocios%rowtype; w public.carteira%rowtype; a public.apps_catalogo%rowtype; pl public.planos%rowtype;
  c public.contratos%rowtype; l public.lancamentos%rowtype; v_disponivel numeric(15,2); v_fat record;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio inválido.' using errcode = 'check_violation'; end if;
  perform public.exigir_membro(n.organizacao_id);
  select * into a from public.apps_catalogo where id = p_app_id;
  if not found or a.negocio_id <> p_negocio_id then raise exception 'App inválido para este negócio.' using errcode = 'check_violation'; end if;
  if not a.ativo then raise exception 'O app está inativo.' using errcode = 'check_violation'; end if;
  if p_valor is null or p_valor < 0 then raise exception 'Informe o valor pago na ativação.' using errcode = 'check_violation'; end if;
  select * into pl from public.planos where id = a.plano_id;
  select * into w from public.carteira where negocio_id = p_negocio_id for update;
  if not found then raise exception 'Configure a carteira do negócio antes de ativar apps.' using errcode = 'check_violation'; end if;
  v_disponivel := case when p_forma_pagamento = 'credito' then w.saldo_credito else w.saldo_dinheiro end;
  if v_disponivel < p_valor then
    raise exception 'Saldo insuficiente (%): disponível %, necessário %.', p_forma_pagamento, to_char(v_disponivel, 'FM999G999G990D00'), to_char(p_valor, 'FM999G999G990D00') using errcode = 'check_violation';
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

  perform set_config('erp.motor', 'on', true);
  -- despesa do consumo só existe quando pago em dinheiro (crédito já foi custeado na recarga)
  if p_forma_pagamento = 'dinheiro' and p_valor > 0 then
    insert into public.lancamentos (organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
                                    conta_id, categoria_id, origem, negocio_id, pessoa_id, contrato_id)
    values (n.organizacao_id, 'despesa', left('Ativação ' || a.nome || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140), p_valor, p_data, p_data, p_data, 'efetivado',
            w.conta_id, w.categoria_consumo_id, 'sistema', p_negocio_id, p_pessoa_id, c.id)
    returning * into l;
    perform public.gerar_movimentos(l.id);
  end if;
  if p_valor > 0 then
    insert into public.transacoes_carteira (organizacao_id, negocio_id, tipo, forma_pagamento, valor, valor_reais, app_id, contrato_id, lancamento_id, data, observacao)
    values (n.organizacao_id, p_negocio_id, 'consumo', p_forma_pagamento, p_valor, case when p_forma_pagamento = 'dinheiro' then p_valor else null end, a.id, c.id, l.id, p_data, p_observacao);
  end if;
  return c;
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. Views
-- -----------------------------------------------------------------------------
create view public.vw_carteira_resumo
with (security_invoker = true) as
select n.id as negocio_id, n.organizacao_id, n.nome as negocio,
       w.id as carteira_id, w.conta_id, w.categoria_consumo_id,
       coalesce(w.saldo_dinheiro, 0) as saldo_dinheiro, coalesce(w.saldo_credito, 0) as saldo_credito,
       coalesce((select sum(t.valor) from public.transacoes_carteira t where t.negocio_id = n.id and t.tipo = 'recarga' and t.forma_pagamento = 'dinheiro'), 0) as total_recargas_dinheiro,
       coalesce((select sum(t.valor) from public.transacoes_carteira t where t.negocio_id = n.id and t.tipo = 'recarga' and t.forma_pagamento = 'credito'), 0) as total_recargas_credito,
       coalesce((select sum(t.valor) from public.transacoes_carteira t where t.negocio_id = n.id and t.tipo = 'consumo' and t.forma_pagamento = 'dinheiro'), 0) as total_consumos_dinheiro,
       coalesce((select sum(t.valor) from public.transacoes_carteira t where t.negocio_id = n.id and t.tipo = 'consumo' and t.forma_pagamento = 'credito'), 0) as total_consumos_credito,
       (select count(*) from public.contratos c join public.apps_catalogo a on a.plano_id = c.plano_id where c.negocio_id = n.id and c.status = 'ativo') as apps_ativos,
       coalesce((select sum(c.valor) from public.contratos c join public.apps_catalogo a on a.plano_id = c.plano_id where c.negocio_id = n.id and c.status = 'ativo'), 0) as anuidades_ativas
  from public.negocios n
  left join public.carteira w on w.negocio_id = n.id
 where n.usa_carteira;

create view public.vw_contratos_app
with (security_invoker = true) as
select c.id as contrato_id, c.organizacao_id, c.negocio_id, a.id as app_id, a.nome as app, c.pessoa_id, c.codigo, c.valor as anuidade,
       c.data_inicio, c.data_fim, c.status,
       t.forma_pagamento, t.valor as valor_pago,
       case when c.status = 'encerrado' then 'cancelado'
            when exists (select 1 from public.lancamentos l where l.contrato_id = c.id and l.status = 'previsto' and l.data_vencimento < current_date) then 'vencido'
            else 'ativo' end as situacao,
       (select min(l.data_vencimento) from public.lancamentos l where l.contrato_id = c.id and l.status = 'previsto') as proximo_vencimento
  from public.contratos c
  join public.apps_catalogo a on a.plano_id = c.plano_id
  left join public.transacoes_carteira t on t.contrato_id = c.id and t.tipo = 'consumo';

grant select on public.vw_carteira_resumo, public.vw_contratos_app to authenticated;

-- -----------------------------------------------------------------------------
-- 8. Permissões das novas assinaturas
-- -----------------------------------------------------------------------------
revoke all on function public.criar_app(uuid, text, numeric),
  public.recarregar_carteira(uuid, public.tipo_saldo_app, numeric, numeric, uuid, date, text),
  public.ativar_app(uuid, uuid, uuid, public.tipo_saldo_app, numeric, date, numeric, integer, text) from public, anon;
grant execute on function public.criar_app(uuid, text, numeric),
  public.recarregar_carteira(uuid, public.tipo_saldo_app, numeric, numeric, uuid, date, text),
  public.ativar_app(uuid, uuid, uuid, public.tipo_saldo_app, numeric, date, numeric, integer, text) to authenticated;

commit;
