-- =============================================================================
-- 0027 · Contratos com fornecedor (despesa) + lançamento automático ao criar
-- =============================================================================
-- Etapa 14. Um contrato passa a poder ser de "Cliente" (receita, como já era) ou
-- "Fornecedor" (despesa). Ao SALVAR o contrato (insert), o sistema já gera o
-- lançamento previsto correspondente — sem precisar clicar em "Gerar faturamento
-- agora" depois. A importação de clientes em massa continua criando contratos de
-- receita e passa a faturar cada um automaticamente também.
-- =============================================================================
create type public.tipo_financeiro_contrato as enum ('receita', 'despesa');
alter table public.contratos add column tipo_financeiro public.tipo_financeiro_contrato not null default 'receita';
alter table public.negocios add column categoria_despesa_id uuid references public.categorias (id) on delete restrict;

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
  if new.categoria_despesa_id is not null then
    select * into k from public.categorias where id = new.categoria_despesa_id;
    if not found or k.organizacao_id <> new.organizacao_id then raise exception 'Categoria de despesa inválida.' using errcode = 'check_violation'; end if;
    if k.tipo <> 'despesa' then raise exception 'A categoria padrão deve ser de despesa.' using errcode = 'check_violation'; end if;
    if not k.ativo and new.categoria_despesa_id is distinct from old.categoria_despesa_id then raise exception 'A categoria padrão está inativa.' using errcode = 'check_violation'; end if;
  end if;
  return new;
end;
$$;

-- Faturamento: agora com dois ramos. Receita = como já era (fidelidade, Indique e Ganhe,
-- Pix na fatura). Despesa = compromisso com fornecedor, direto na categoria/conta de despesa
-- do negócio, sem programa de fidelidade nem desconto de indicação (são benefícios do cliente).
create or replace function public.faturar_contrato(p_contrato uuid, p_ate date, out gerados integer, out pendencia text)
language plpgsql
set search_path = public
as $$
declare
  c public.contratos%rowtype;
  n public.negocios%rowtype;
  pl public.planos%rowtype;
  v_conta uuid; v_cat uuid; v_comp date; v_venc date; l public.lancamentos%rowtype;
  v_desc numeric(14,2); v_valor numeric(14,2); v_motivos text;
begin
  gerados := 0; pendencia := null;
  select * into c from public.contratos where id = p_contrato;
  if not found or c.status <> 'ativo' or not c.faturamento_automatico then return; end if;
  if not exists (select 1 from public.competencias_pendentes(c.id, p_ate)) then return; end if;
  select * into n from public.negocios where id = c.negocio_id;
  select * into pl from public.planos where id = c.plano_id;
  v_conta := coalesce(c.conta_id, n.conta_padrao_id);
  v_cat := case when c.tipo_financeiro = 'despesa' then n.categoria_despesa_id else n.categoria_receita_id end;
  if v_conta is null then pendencia := case when c.tipo_financeiro = 'despesa' then 'Sem conta de pagamento (no contrato ou padrão do negócio).' else 'Sem conta de recebimento (no contrato ou padrão do negócio).' end; return; end if;
  if v_cat is null then pendencia := case when c.tipo_financeiro = 'despesa' then 'Negócio sem categoria de despesa padrão.' else 'Negócio sem categoria de receita padrão.' end; return; end if;
  if not exists (select 1 from public.contas where id = v_conta and ativo) then pendencia := case when c.tipo_financeiro = 'despesa' then 'Conta de pagamento inativa.' else 'Conta de recebimento inativa.' end; return; end if;
  if not exists (select 1 from public.categorias where id = v_cat and ativo) then pendencia := 'Categoria padrão inativa.'; return; end if;
  if c.valor <= 0 then pendencia := 'Contrato com valor zero.'; return; end if;

  perform set_config('erp.motor', 'on', true);
  for v_comp in select * from public.competencias_pendentes(c.id, p_ate) order by 1 loop
    v_venc := public.data_vencimento_no_mes(v_comp, c.dia_vencimento);
    if c.tipo_financeiro = 'receita' then
      perform public.fidelidade_registrar_premio(c.id, v_comp);
      select coalesce(sum(d.valor), 0), string_agg(d.motivo, '; ' order by d.criado_em) into v_desc, v_motivos
        from public.descontos_contrato d where d.contrato_id = c.id and d.lancamento_id is null;
    else
      v_desc := 0; v_motivos := null;
    end if;
    v_valor := case when v_desc >= c.valor then c.valor else c.valor - v_desc end;
    insert into public.lancamentos (
      organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
      conta_id, categoria_id, origem, negocio_id, pessoa_id, contrato_id, observacao, cancelado_em, motivo_cancelamento
    ) values (
      c.organizacao_id, c.tipo_financeiro::text::public.tipo_lancamento,
      left(pl.nome || ' · ' || to_char(v_comp, 'MM/YYYY') || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140),
      v_valor, v_venc, v_venc, null, (case when v_desc >= c.valor then 'cancelado' else 'previsto' end)::public.status_lancamento,
      v_conta, v_cat, 'faturamento', c.negocio_id, c.pessoa_id, c.id,
      case when v_desc >= c.valor then left('Mês grátis (' || v_motivos || ').', 500)
           when v_desc > 0 then left('Desconto aplicado: ' || public.moeda_br(v_desc) || ' (' || v_motivos || ').', 500) end,
      case when v_desc >= c.valor then now() end,
      case when v_desc >= c.valor then left('Mês grátis: ' || v_motivos, 200) end
    ) returning * into l;
    if v_desc > 0 then
      update public.descontos_contrato set lancamento_id = l.id where contrato_id = c.id and lancamento_id is null;
    end if;
    insert into public.faturamentos (organizacao_id, contrato_id, competencia, lancamento_id) values (c.organizacao_id, c.id, v_comp, l.id);
    gerados := gerados + 1;
  end loop;
end;
$$;

-- O vínculo automático da pessoa com o negócio segue o tipo do contrato: cliente (receita) ou
-- fornecedor (despesa) — antes era sempre "cliente".
create or replace function public.tg_contratos_vinculo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  insert into public.pessoa_negocio_vinculos (organizacao_id, pessoa_id, negocio_id, papel)
  values (new.organizacao_id, new.pessoa_id, new.negocio_id, case when new.tipo_financeiro = 'despesa' then 'fornecedor' else 'cliente' end::public.papel_vinculo)
  on conflict (pessoa_id, negocio_id, papel) do update set ativo = true;
  return new;
end;
$$;

-- Ao criar o contrato, já gera a primeira competência (a do mês de início) como lançamento
-- previsto — nenhum passo manual depois. Competências atrasadas (contrato retroativo) e as
-- seguintes continuam a cargo de "Gerar faturamento agora" e do cron diário, como já era.
create or replace function public.tg_contratos_faturar_ao_criar()
returns trigger
language plpgsql
security definer  -- faturar_contrato é revogada de authenticated (só chamável internamente); o trigger roda no insert do cliente
set search_path = public
as $$
declare v_gerados integer; v_pendencia text;
begin
  select gerados, pendencia into v_gerados, v_pendencia
    from public.faturar_contrato(new.id, date_trunc('month', coalesce(new.faturar_desde, new.data_inicio))::date);
  if v_pendencia is not null then
    raise warning 'Contrato #% criado sem lançamento automático: %', new.codigo, v_pendencia;
  end if;
  return new;
end;
$$;
create trigger contratos_c_faturar_ao_criar after insert on public.contratos for each row execute function public.tg_contratos_faturar_ao_criar();
revoke all on function public.tg_contratos_faturar_ao_criar() from public, anon, authenticated;
