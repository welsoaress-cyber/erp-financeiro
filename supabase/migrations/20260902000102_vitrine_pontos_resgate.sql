-- =============================================================================
-- 0102 · Etapa 58B — Vitrine de prêmios + resgate de pontos
-- =============================================================================
-- Cliente troca o saldo de pontos por:
--   · Prêmio físico: catálogo (nome, foto, item do Estoque categoria Brindes,
--     preço em R$ escolhido pelo dono). Custo em pontos = arredonda pra cima
--     (preço / R$0,22). Escolha no portal debita os pontos na hora (trava,
--     sem troca); entrega (baixa o estoque, congela o custo real) é sempre
--     confirmada pelo proprietário — mesmo padrão do Indique e Ganhe.
--   · Desconto na próxima fatura em aberto: R$0,25 por ponto, mínimo 4 pontos
--     (R$1,00), não passa do valor da fatura (100% dela vira cortesia). Sem
--     catálogo — o cliente informa quantos pontos quer converter. Imediato.
-- =============================================================================

alter type public.origem_movimentacao_estoque add value if not exists 'resgate_pontos';

create type public.tipo_resgate_pontos as enum ('brinde', 'desconto');

-- saída de estoque passa a aceitar a origem 'resgate_pontos' (entrega de prêmio da vitrine de pontos)
create or replace function public.saida_estoque(p_item_id uuid, p_quantidade numeric, p_origem text, p_data date, p_pessoa_id uuid, p_contrato_id uuid, p_observacao text, p_instalacao_id uuid)
returns public.estoque_movimentacoes
language plpgsql
security definer
set search_path = public
as $$
declare it public.estoque_itens%rowtype; m public.estoque_movimentacoes%rowtype;
begin
  select * into it from public.estoque_itens where id = p_item_id;
  if not found then raise exception 'Item não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(it.organizacao_id);
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade da saída deve ser maior que zero.' using errcode = 'check_violation'; end if;
  if p_origem not in ('instalacao', 'perda', 'brinde', 'resgate_pontos') then raise exception 'Origem de saída inválida.' using errcode = 'check_violation'; end if;
  if p_quantidade > it.quantidade_atual then
    raise exception 'Saída de % maior que o estoque disponível (% %).', it.nome, it.quantidade_atual, it.unidade_medida using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.estoque_itens set quantidade_atual = quantidade_atual - p_quantidade where id = p_item_id;
  insert into public.estoque_movimentacoes (organizacao_id, negocio_id, item_id, tipo, origem, quantidade, valor_unitario, valor_total, data, pessoa_id, contrato_id, instalacao_id, observacao, usuario_id)
  values (it.organizacao_id, it.negocio_id, p_item_id, 'saida', p_origem::public.origem_movimentacao_estoque, p_quantidade, it.valor_custo, round(p_quantidade * it.valor_custo, 2), coalesce(p_data, current_date), p_pessoa_id, p_contrato_id, p_instalacao_id, p_observacao, auth.uid())
  returning * into m;
  return m;
end;
$$;

-- -----------------------------------------------------------------------------
-- 1. Catálogo de prêmios físicos
-- -----------------------------------------------------------------------------
create table public.pontos_premios (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id     uuid not null references public.negocios (id),
  nome           text not null check (char_length(btrim(nome)) between 2 and 80),
  foto           text check (foto is null or (foto like 'data:image/%' and char_length(foto) <= 400000)),
  item_id        uuid not null references public.estoque_itens (id) on delete restrict,
  valor_reais    numeric(14,2) not null check (valor_reais > 0),
  pontos_custo   int not null check (pontos_custo > 0),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
comment on table public.pontos_premios is 'Vitrine de prêmios físicos do programa de pontos (etapa 58B). pontos_custo = ceil(valor_reais / 0,22), calculado pelo motor.';
create index pontos_premios_negocio on public.pontos_premios (negocio_id);
create trigger pontos_premios_atualizado before update on public.pontos_premios for each row execute function public.tg_atualizado_em();
create trigger pontos_premios_auditoria after insert or update or delete on public.pontos_premios for each row execute function public.tg_auditoria();

create function public.tg_pontos_premios_protecao()
returns trigger language plpgsql set search_path = public as $$
declare it public.estoque_itens%rowtype;
begin
  if tg_op = 'UPDATE' and (new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id) then
    raise exception 'O prêmio não muda de negócio.' using errcode = 'check_violation';
  end if;
  perform public.validar_negocio(new.negocio_id, new.organizacao_id, tg_op = 'INSERT');
  select * into it from public.estoque_itens where id = new.item_id;
  if not found or it.organizacao_id <> new.organizacao_id then
    raise exception 'Item de estoque inválido.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.estoque_categorias ec where ec.id = it.categoria_id and lower(ec.nome) like 'brinde%') then
    raise exception 'O prêmio precisa apontar para um item da categoria Brindes do Estoque.' using errcode = 'check_violation';
  end if;
  new.nome := btrim(new.nome);
  new.pontos_custo := ceil(new.valor_reais / 0.22)::int;
  return new;
end; $$;
create trigger pontos_premios_protecao before insert or update on public.pontos_premios for each row execute function public.tg_pontos_premios_protecao();

alter table public.pontos_premios enable row level security;
create policy pontos_premios_select on public.pontos_premios for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy pontos_premios_insert on public.pontos_premios for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy pontos_premios_update on public.pontos_premios for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.pontos_premios from public, anon, authenticated;
grant select, insert, update on public.pontos_premios to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Resgates (histórico imutável) + saldo (ganhos − resgates)
-- -----------------------------------------------------------------------------
create table public.pontos_resgates (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  pessoa_id      uuid not null references public.pessoas (id) on delete restrict,
  tipo           public.tipo_resgate_pontos not null,
  premio_id      uuid references public.pontos_premios (id) on delete restrict,
  lancamento_id  uuid references public.lancamentos (id) on delete restrict,
  pontos         int not null check (pontos > 0),
  valor_reais    numeric(14,2) not null check (valor_reais > 0),
  entregue_em    timestamptz,
  criado_em      timestamptz not null default now(),
  check ((tipo = 'brinde') = (premio_id is not null)),
  check ((tipo = 'desconto') = (lancamento_id is not null))
);
comment on table public.pontos_resgates is 'Um registro por resgate de pontos (etapa 58B). Imutável. Brinde: entregue_em preenchido quando o proprietário confirma a entrega. Desconto: aplicado na hora.';
create index pontos_resgates_saldo_idx on public.pontos_resgates (pessoa_id, negocio_id);
alter table public.pontos_resgates enable row level security;
create policy pontos_resgates_org on public.pontos_resgates for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.pontos_resgates from public, anon, authenticated;
grant select on public.pontos_resgates to authenticated;

drop view public.vw_saldo_pontos;
create view public.vw_saldo_pontos with (security_invoker = true) as
select pessoa_id, negocio_id, sum(pontos)::int as saldo from (
  select pessoa_id, negocio_id, pontos from public.pontos_pontualidade
  union all
  select pessoa_id, negocio_id, -pontos from public.pontos_resgates
) x
group by pessoa_id, negocio_id;
grant select on public.vw_saldo_pontos to authenticated;
comment on view public.vw_saldo_pontos is 'Saldo de pontos por pessoa/negócio: soma dos ganhos (pontos_pontualidade) menos os resgates (pontos_resgates).';

-- -----------------------------------------------------------------------------
-- 3. Motor: resgatar prêmio físico (portal), confirmar entrega (admin),
--    resgatar desconto em fatura (portal)
-- -----------------------------------------------------------------------------
create function public.portal_resgatar_premio_pontos(p_premio_id uuid)
returns public.pontos_resgates
language plpgsql
security definer
set search_path = public
as $$
declare v_pessoa uuid; pr public.pontos_premios%rowtype; it public.estoque_itens%rowtype; v_saldo int; r public.pontos_resgates%rowtype;
begin
  v_pessoa := public.portal_pessoa();
  select * into pr from public.pontos_premios where id = p_premio_id and ativo;
  if not found then raise exception 'Prêmio não encontrado ou indisponível.' using errcode = 'no_data_found'; end if;
  select * into it from public.estoque_itens where id = pr.item_id;
  if not found or not it.ativo or it.quantidade_atual < 1 then
    raise exception 'Prêmio sem saldo em estoque no momento — tente mais tarde.' using errcode = 'check_violation';
  end if;
  select coalesce(saldo, 0) into v_saldo from public.vw_saldo_pontos where pessoa_id = v_pessoa and negocio_id = pr.negocio_id;
  if coalesce(v_saldo, 0) < pr.pontos_custo then
    raise exception 'Saldo insuficiente: precisa de % pontos, você tem %.', pr.pontos_custo, coalesce(v_saldo, 0) using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  insert into public.pontos_resgates (organizacao_id, negocio_id, pessoa_id, tipo, premio_id, pontos, valor_reais)
  values (pr.organizacao_id, pr.negocio_id, v_pessoa, 'brinde', pr.id, pr.pontos_custo, pr.valor_reais)
  returning * into r;
  return r;
end;
$$;
revoke all on function public.portal_resgatar_premio_pontos(uuid) from public, anon;
grant execute on function public.portal_resgatar_premio_pontos(uuid) to authenticated;

create function public.entregar_premio_pontos(p_resgate_id uuid, p_observacao text default null)
returns public.pontos_resgates
language plpgsql
security definer
set search_path = public
as $$
declare r public.pontos_resgates%rowtype; pr public.pontos_premios%rowtype; it public.estoque_itens%rowtype;
begin
  select * into r from public.pontos_resgates where id = p_resgate_id for update;
  if not found then raise exception 'Resgate não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(r.organizacao_id);
  if r.tipo <> 'brinde' then raise exception 'Só resgate de prêmio físico tem entrega.' using errcode = 'check_violation'; end if;
  if r.entregue_em is not null then raise exception 'Este resgate já foi entregue.' using errcode = 'check_violation'; end if;
  select * into pr from public.pontos_premios where id = r.premio_id;
  select * into it from public.estoque_itens where id = pr.item_id;
  if it.quantidade_atual < 1 then
    raise exception 'Item "%" sem saldo em estoque — compre/ajuste antes de entregar.', it.nome using errcode = 'check_violation';
  end if;
  perform public.saida_estoque(pr.item_id, 1, 'resgate_pontos', current_date, r.pessoa_id, null,
    coalesce(p_observacao, 'Resgate de pontos por pontualidade — ' || pr.nome));
  perform set_config('erp.motor', 'on', true);
  update public.pontos_resgates set entregue_em = now() where id = p_resgate_id returning * into r;
  return r;
end;
$$;
revoke all on function public.entregar_premio_pontos(uuid, text) from public, anon;
grant execute on function public.entregar_premio_pontos(uuid, text) to authenticated;

create function public.portal_resgatar_desconto_pontos(p_negocio_id uuid, p_pontos int)
returns public.pontos_resgates
language plpgsql
security definer
set search_path = public
as $$
declare v_pessoa uuid; v_saldo int; v_valor_pedido numeric(14,2); v_fatura public.lancamentos%rowtype;
        v_valor_aplicado numeric(14,2); v_pontos_gastos int; r public.pontos_resgates%rowtype;
begin
  v_pessoa := public.portal_pessoa();
  if p_pontos is null or p_pontos < 4 then
    raise exception 'Mínimo de 4 pontos (R$ 1,00) por resgate.' using errcode = 'check_violation';
  end if;
  select coalesce(saldo, 0) into v_saldo from public.vw_saldo_pontos where pessoa_id = v_pessoa and negocio_id = p_negocio_id;
  if coalesce(v_saldo, 0) < p_pontos then
    raise exception 'Saldo insuficiente: você tem % pontos.', coalesce(v_saldo, 0) using errcode = 'check_violation';
  end if;
  select l.* into v_fatura
    from public.lancamentos l
    join public.contratos c on c.id = l.contrato_id
   where c.pessoa_id = v_pessoa and l.negocio_id = p_negocio_id and l.tipo = 'receita' and l.status = 'previsto'
   order by l.data_vencimento asc
   limit 1;
  if not found then
    raise exception 'Nenhuma fatura em aberto para aplicar o desconto.' using errcode = 'no_data_found';
  end if;
  v_valor_pedido := round(p_pontos * 0.25, 2);
  v_valor_aplicado := least(v_valor_pedido, v_fatura.valor);
  v_pontos_gastos := ceil(v_valor_aplicado / 0.25)::int;
  perform set_config('erp.motor', 'on', true);
  if v_valor_aplicado >= v_fatura.valor then
    -- 100% da fatura: cancela direto (não usa cancelar_lancamento, que exige ser membro do negócio — aqui quem autoriza é ser dono da fatura)
    update public.lancamentos
       set status = 'cancelado', cancelado_em = now(),
           motivo_cancelamento = 'Cortesia — resgate de pontos por pontualidade (100% da fatura).', data_efetivacao = null
     where id = v_fatura.id;
    perform public.gerar_movimentos(v_fatura.id);
  else
    update public.lancamentos set valor = valor - v_valor_aplicado where id = v_fatura.id;
  end if;
  insert into public.pontos_resgates (organizacao_id, negocio_id, pessoa_id, tipo, lancamento_id, pontos, valor_reais)
  values (v_fatura.organizacao_id, p_negocio_id, v_pessoa, 'desconto', v_fatura.id, v_pontos_gastos, v_valor_aplicado)
  returning * into r;
  return r;
end;
$$;
revoke all on function public.portal_resgatar_desconto_pontos(uuid, int) from public, anon;
grant execute on function public.portal_resgatar_desconto_pontos(uuid, int) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Portal: saldo, extrato e vitrine
-- -----------------------------------------------------------------------------
create function public.portal_pontos_saldo()
returns table (negocio_id uuid, negocio text, saldo int)
language sql
stable
security definer
set search_path = public
as $$
  select s.negocio_id, n.nome, s.saldo
    from public.vw_saldo_pontos s
    join public.negocios n on n.id = s.negocio_id
   where s.pessoa_id = public.portal_pessoa();
$$;
revoke all on function public.portal_pontos_saldo() from public, anon;
grant execute on function public.portal_pontos_saldo() to authenticated;

create function public.portal_pontos_extrato()
returns table (quando timestamptz, negocio text, descricao text, pontos int)
language sql
stable
security definer
set search_path = public
as $$
  select pp.criado_em, n.nome, 'Fatura paga adiantada: ' || l.descricao, pp.pontos
    from public.pontos_pontualidade pp
    join public.negocios n on n.id = pp.negocio_id
    join public.lancamentos l on l.id = pp.lancamento_id
   where pp.pessoa_id = public.portal_pessoa()
  union all
  select r.criado_em, n.nome,
         case when r.tipo = 'brinde' then 'Resgate: ' || coalesce(pr.nome, 'prêmio') else 'Desconto de ' || public.moeda_br(r.valor_reais) || ' na fatura' end,
         -r.pontos
    from public.pontos_resgates r
    join public.negocios n on n.id = r.negocio_id
    left join public.pontos_premios pr on pr.id = r.premio_id
   where r.pessoa_id = public.portal_pessoa()
   order by 1 desc;
$$;
revoke all on function public.portal_pontos_extrato() from public, anon;
grant execute on function public.portal_pontos_extrato() to authenticated;

create function public.portal_pontos_vitrine(p_negocio_id uuid)
returns table (id uuid, nome text, foto text, pontos_custo int)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.nome, p.foto, p.pontos_custo
    from public.pontos_premios p
    join public.estoque_itens it on it.id = p.item_id
   where p.negocio_id = p_negocio_id and p.ativo and it.ativo and it.quantidade_atual >= 1
   order by p.pontos_custo;
$$;
revoke all on function public.portal_pontos_vitrine(uuid) from public, anon;
grant execute on function public.portal_pontos_vitrine(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Relatório: ROI da campanha (resgates)
-- -----------------------------------------------------------------------------
create view public.vw_rel_pontos_resgates with (security_invoker = true) as
select r.id, r.organizacao_id, r.negocio_id, n.nome as negocio, p.nome as cliente,
       (case r.tipo when 'brinde' then 'Prêmio físico' else 'Desconto em fatura' end) as tipo,
       coalesce(pr.nome, '—') as premio, r.pontos, r.valor_reais,
       (case when r.tipo = 'brinde' then (case when r.entregue_em is not null then 'Entregue' else 'Aguardando entrega' end) else 'Aplicado' end) as situacao,
       r.criado_em, r.entregue_em
  from public.pontos_resgates r
  join public.negocios n on n.id = r.negocio_id
  join public.pessoas p on p.id = r.pessoa_id
  left join public.pontos_premios pr on pr.id = r.premio_id;
grant select on public.vw_rel_pontos_resgates to authenticated;
