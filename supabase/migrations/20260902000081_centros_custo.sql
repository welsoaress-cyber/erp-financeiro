-- =============================================================================
-- 0081 · CENTROS DE CUSTO — 54A (Etapa 54)
-- =============================================================================
-- Eixo de custo que faltava: departamento / projeto / ponto de rede (POP, CTO),
-- dentro de cada negócio. NÃO substitui negócio (centro de custo de 1º nível),
-- nem pessoa/contrato/técnico (custo por cliente/contrato/técnico já vem dos
-- vínculos existentes). Opcional no lançamento: sem centro = "Geral".
-- Uma tabela; auditoria pelo trigger genérico; sem exclusão (só inativar).
-- =============================================================================
create type public.tipo_centro_custo as enum ('departamento', 'projeto', 'ponto_rede', 'outro');

create table public.centros_custo (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id uuid not null references public.negocios (id) on delete restrict,
  nome text not null check (char_length(btrim(nome)) between 2 and 80),
  descricao text check (descricao is null or char_length(descricao) <= 300),
  tipo public.tipo_centro_custo not null default 'departamento',
  referencia_id uuid references public.ctos (id) on delete restrict, -- ponto_rede: POP/CEO/CTO
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create unique index centros_custo_nome_unq on public.centros_custo (negocio_id, lower(btrim(nome)));
create index centros_custo_negocio_idx on public.centros_custo (organizacao_id, negocio_id);
comment on table public.centros_custo is 'Centro de custo dentro do negócio (departamento, projeto, ponto de rede). Nulo no lançamento = Geral.';

create or replace function public.tg_centros_custo_validar()
returns trigger
language plpgsql
set search_path = public
as $$
declare v_neg public.negocios%rowtype; v_cto public.ctos%rowtype;
begin
  select * into v_neg from public.negocios where id = new.negocio_id;
  if not found or v_neg.organizacao_id <> new.organizacao_id then
    raise exception 'Negócio inválido para o centro de custo.' using errcode = 'check_violation';
  end if;
  if tg_op = 'UPDATE' and new.negocio_id <> old.negocio_id then
    raise exception 'O centro de custo não muda de negócio.' using errcode = 'check_violation';
  end if;
  if new.tipo = 'ponto_rede' then
    if new.referencia_id is null then raise exception 'Centro de custo de ponto de rede precisa do ponto (POP/CEO/CTO).' using errcode = 'check_violation'; end if;
    select * into v_cto from public.ctos where id = new.referencia_id;
    if not found or v_cto.organizacao_id <> new.organizacao_id or v_cto.negocio_id <> new.negocio_id then
      raise exception 'Ponto de rede inválido para este negócio.' using errcode = 'check_violation';
    end if;
  else
    new.referencia_id := null;
  end if;
  new.nome := regexp_replace(btrim(new.nome), '\s+', ' ', 'g');
  return new;
end;
$$;
create trigger centros_custo_validar before insert or update on public.centros_custo for each row execute function public.tg_centros_custo_validar();
create trigger centros_custo_atualizado before update on public.centros_custo for each row execute function public.tg_atualizado_em();
create trigger centros_custo_auditoria after insert or update or delete on public.centros_custo for each row execute function public.tg_auditoria();

alter table public.centros_custo enable row level security;
create policy centros_custo_select on public.centros_custo for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy centros_custo_insert on public.centros_custo for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy centros_custo_update on public.centros_custo for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.centros_custo from anon;
grant select, insert, update on public.centros_custo to authenticated;
revoke all on function public.tg_centros_custo_validar() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Lançamentos e contratos apontam (opcionalmente) para um centro do MESMO negócio
-- -----------------------------------------------------------------------------
alter table public.lancamentos add column centro_custo_id uuid references public.centros_custo (id) on delete restrict;
create index lancamentos_centro_custo_idx on public.lancamentos (centro_custo_id) where centro_custo_id is not null;
alter table public.contratos add column centro_custo_id uuid references public.centros_custo (id) on delete restrict;

create or replace function public.validar_centro_custo(p_centro uuid, p_organizacao uuid, p_negocio uuid, p_exigir_ativo boolean)
returns void
language plpgsql
stable
set search_path = public
as $$
declare cc public.centros_custo%rowtype;
begin
  if p_centro is null then return; end if;
  select * into cc from public.centros_custo where id = p_centro;
  if not found or cc.organizacao_id <> p_organizacao then raise exception 'Centro de custo inválido.' using errcode = 'check_violation'; end if;
  if p_negocio is distinct from cc.negocio_id then raise exception 'O centro de custo pertence a outro negócio.' using errcode = 'check_violation'; end if;
  if p_exigir_ativo and not cc.ativo then raise exception 'Centro de custo inativo.' using errcode = 'check_violation'; end if;
end;
$$;
revoke all on function public.validar_centro_custo(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function public.validar_centro_custo(uuid, uuid, uuid, boolean) to authenticated; -- chamada por trigger que roda como o usuário (mesmo padrão de validar_negocio)

create or replace function public.tg_lancamentos_centro_custo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform public.validar_centro_custo(new.centro_custo_id, new.organizacao_id, new.negocio_id,
    tg_op = 'INSERT' or new.centro_custo_id is distinct from old.centro_custo_id);
  return new;
end;
$$;
create trigger lancamentos_centro_custo before insert or update on public.lancamentos for each row execute function public.tg_lancamentos_centro_custo();
create trigger contratos_centro_custo before insert or update on public.contratos for each row execute function public.tg_lancamentos_centro_custo();
revoke all on function public.tg_lancamentos_centro_custo() from public, anon, authenticated;

-- Motor: definir/trocar o centro de custo de um lançamento (auditado como qualquer escrita do motor)
create function public.definir_centro_custo_lancamento(p_id uuid, p_centro uuid)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare l public.lancamentos%rowtype;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.centro_custo_id is not distinct from p_centro then return l; end if;
  perform set_config('erp.motor', 'on', true);
  update public.lancamentos set centro_custo_id = p_centro where id = p_id returning * into l;
  return l;
end;
$$;
revoke all on function public.definir_centro_custo_lancamento(uuid, uuid) from public, anon;
grant execute on function public.definir_centro_custo_lancamento(uuid, uuid) to authenticated;

-- Faturamento de contrato (fornecedor ou cliente) herda o centro do contrato
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
  if c.cortesia then
    -- cortesia (0080): a fatura aparece, mas não conta — nasce CANCELADA (mesmo caminho do "mês grátis"),
    -- com o valor de tabela do plano só como referência. Cancelado não entra em previsto/realizado/saldo,
    -- cobrança nem bloqueio; o portal mostra "Grátis". Plano com valor de tabela 0: nada a mostrar.
    if coalesce(pl.valor_tabela, 0) <= 0 then return; end if;
    perform set_config('erp.motor', 'on', true);
    for v_comp in select * from public.competencias_pendentes(c.id, p_ate) order by 1 loop
      v_venc := public.data_vencimento_no_mes(v_comp, c.dia_vencimento);
      insert into public.lancamentos (
        organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
        conta_id, categoria_id, origem, negocio_id, pessoa_id, contrato_id, observacao, cancelado_em, motivo_cancelamento, centro_custo_id
      ) values (
        c.organizacao_id, c.tipo_financeiro::text::public.tipo_lancamento,
        left(pl.nome || ' · ' || to_char(v_comp, 'MM/YYYY') || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140),
        pl.valor_tabela, v_venc, v_venc, null, 'cancelado',
        v_conta, v_cat, 'faturamento', c.negocio_id, c.pessoa_id, c.id,
        'Cortesia (sem cobrança).', now(), 'Cortesia', c.centro_custo_id
      ) returning * into l;
      insert into public.faturamentos (organizacao_id, contrato_id, competencia, lancamento_id) values (c.organizacao_id, c.id, v_comp, l.id);
      gerados := gerados + 1;
    end loop;
    return;
  end if;
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
      conta_id, categoria_id, origem, negocio_id, pessoa_id, contrato_id, observacao, cancelado_em, motivo_cancelamento, centro_custo_id
    ) values (
      c.organizacao_id, c.tipo_financeiro::text::public.tipo_lancamento,
      left(pl.nome || ' · ' || to_char(v_comp, 'MM/YYYY') || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140),
      v_valor, v_venc, v_venc, null, (case when v_desc >= c.valor then 'cancelado' else 'previsto' end)::public.status_lancamento,
      v_conta, v_cat, 'faturamento', c.negocio_id, c.pessoa_id, c.id,
      case when v_desc >= c.valor then left('Mês grátis (' || v_motivos || ').', 500)
           when v_desc > 0 then left('Desconto aplicado: ' || public.moeda_br(v_desc) || ' (' || v_motivos || ').', 500) end,
      case when v_desc >= c.valor then now() end,
      case when v_desc >= c.valor then left('Mês grátis: ' || v_motivos, 200) end,
      c.centro_custo_id
    ) returning * into l;
    if v_desc > 0 then
      update public.descontos_contrato set lancamento_id = l.id where contrato_id = c.id and lancamento_id is null;
    end if;
    insert into public.faturamentos (organizacao_id, contrato_id, competencia, lancamento_id) values (c.organizacao_id, c.id, v_comp, l.id);
    gerados := gerados + 1;
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- Relatórios: lançamentos ganham o centro; gastos por centro de custo (Central)
-- -----------------------------------------------------------------------------
create or replace view public.vw_rel_lancamentos
with (security_invoker = true) as
select l.id, l.organizacao_id, l.tipo, l.status, l.descricao, l.valor,
       l.data_competencia, l.data_vencimento, l.data_efetivacao, l.origem,
       l.conta_id, ct.nome as conta,
       l.categoria_id, c.nome as categoria, coalesce(c.natureza, 'operacional'::public.natureza_categoria) as natureza,
       l.negocio_id, coalesce(n.nome, 'Pessoal') as negocio,
       l.pessoa_id, p.nome as pessoa,
       l.contrato_id, k.codigo as contrato_codigo,
       l.centro_custo_id, coalesce(cc.nome, 'Geral') as centro_custo
  from public.lancamentos l
  left join public.contas ct on ct.id = l.conta_id
  left join public.categorias c on c.id = l.categoria_id
  left join public.negocios n on n.id = l.negocio_id
  left join public.pessoas p on p.id = l.pessoa_id
  left join public.contratos k on k.id = l.contrato_id
  left join public.centros_custo cc on cc.id = l.centro_custo_id
 where l.tipo in ('receita', 'despesa');

create view public.vw_rel_gastos_centro_custo
with (security_invoker = true) as
select l.organizacao_id, l.negocio_id,
       l.centro_custo_id, coalesce(cc.nome, 'Geral') as centro_custo, cc.tipo as tipo_centro,
       date_trunc('month', l.data_competencia)::date as mes,
       l.status,
       coalesce(c.natureza, 'operacional'::public.natureza_categoria) as natureza,
       sum(l.valor)::numeric(14,2) as valor,
       count(*)::int as lancamentos
  from public.lancamentos l
  left join public.centros_custo cc on cc.id = l.centro_custo_id
  left join public.categorias c on c.id = l.categoria_id
 where l.tipo = 'despesa' and l.status in ('previsto', 'efetivado')
 group by l.organizacao_id, l.negocio_id, l.centro_custo_id, cc.nome, cc.tipo, date_trunc('month', l.data_competencia), l.status, c.natureza;
grant select on public.vw_rel_gastos_centro_custo to authenticated;
