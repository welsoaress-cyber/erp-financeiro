-- =============================================================================
-- 0093 · Etapa 55B — Compras: Recebimento com nota e lançamento financeiro
-- =============================================================================
-- Recebimento é o momento em que o material chega, a nota (opcional) é
-- registrada e a obrigação financeira nasce. Regras:
-- - Recebimento é imutável (auditoria). Correção = novo recebimento.
-- - Cada item recebe uma quantidade parcial ou total; o pedido fica
--   `recebido_parcial` até fechar tudo, depois `recebido`.
-- - Divergência (recebido ≠ pedido; nota ≠ soma) NÃO trava — só reporta.
-- - Item destino 'estoque' com item_id preenchido → dispara entrada_estoque
--   (motor de estoque) com origem 'compra' e amarra o lancamento_id.
-- - Um lançamento à vista (parcelas ≤ 1) ou N parcelas mensais via
--   criar_lancamento (recorrente). Cartão de crédito → previsto, senão
--   status conforme `p_pago`. Amarrado ao recebimento por lancamento_id.
-- - Itens destino patrimonio/comodato/despesa/servico: entram no
--   recebimento (histórico) e no lançamento, mas a integração completa
--   fica para a etapa 55C. Aqui apenas registram-se.
-- =============================================================================

create table public.compra_recebimentos (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  compra_id uuid not null references public.compras (id),
  data date not null default current_date,
  conferido_por uuid,                            -- auth.uid()
  nota_numero text check (nota_numero is null or char_length(nota_numero) <= 40),
  nota_chave text check (nota_chave is null or char_length(nota_chave) <= 60),
  nota_valor numeric(12,2) check (nota_valor is null or nota_valor >= 0),
  lancamento_id uuid references public.lancamentos (id),
  observacao text check (observacao is null or char_length(observacao) <= 300),
  criado_em timestamptz not null default now()
);
create index compra_recebimentos_compra on public.compra_recebimentos (compra_id, data desc);

create table public.compra_recebimento_itens (
  id uuid primary key default gen_random_uuid(),
  recebimento_id uuid not null references public.compra_recebimentos (id) on delete cascade,
  compra_item_id uuid not null references public.compra_itens (id),
  quantidade numeric(12,2) not null check (quantidade > 0),
  numero_serie text check (numero_serie is null or char_length(numero_serie) <= 60),
  observacao text check (observacao is null or char_length(observacao) <= 200)
);
create index compra_recebimento_itens_receb on public.compra_recebimento_itens (recebimento_id);

-- Recebimento é imutável fora do motor
create or replace function public.tg_recebimento_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('erp.motor', true), '') <> 'on' then
    raise exception 'Recebimento só pelo motor (registrar_recebimento_compra).' using errcode = 'insufficient_privilege';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Recebimento é imutável (registre um novo para corrigir).' using errcode = 'check_violation';
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function public.tg_recebimento_protecao() from public, anon, authenticated;
create trigger compra_recebimentos_protecao before insert or update or delete on public.compra_recebimentos for each row execute function public.tg_recebimento_protecao();
create trigger compra_recebimento_itens_protecao before update or delete on public.compra_recebimento_itens for each row execute function public.tg_recebimento_protecao();

-- Motor: registrar_recebimento_compra
-- p_itens: jsonb array [{ "compra_item_id": uuid, "quantidade": numeric, "numero_serie"?: text, "observacao"?: text }]
create function public.registrar_recebimento_compra(
  p_compra_id uuid,
  p_itens jsonb,
  p_data date default current_date,
  p_nota_numero text default null,
  p_nota_chave text default null,
  p_nota_valor numeric default null,
  p_observacao text default null,
  p_conta_id uuid default null,
  p_pago boolean default false,
  p_parcelas integer default 1,
  p_categoria_padrao_id uuid default null
)
returns public.compra_recebimentos
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.compras%rowtype;
  reb public.compra_recebimentos%rowtype;
  linha jsonb; ci public.compra_itens%rowtype; v_recebida numeric; v_qtd numeric;
  v_total_pedido numeric := 0; v_total_recebido numeric := 0;
  v_valor_lanc numeric := 0; v_categoria uuid; v_desc text;
  v_lanc public.lancamentos%rowtype;
  v_frete_prop numeric; v_desc_prop numeric; v_soma_itens numeric := 0;
  v_data_venc date;
  v_conta public.contas%rowtype;
  v_ehcartao boolean := false;
begin
  select * into c from public.compras where id = p_compra_id;
  if not found then raise exception 'Pedido não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(c.organizacao_id);
  if c.status not in ('aberto', 'recebido_parcial') then
    raise exception 'Pedido % não aceita recebimento.', c.status using errcode = 'check_violation';
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Informe ao menos um item recebido.' using errcode = 'check_violation';
  end if;
  if p_conta_id is null then raise exception 'Escolha a conta de pagamento.' using errcode = 'check_violation'; end if;
  select * into v_conta from public.contas where id = p_conta_id and organizacao_id = c.organizacao_id;
  if not found then raise exception 'Conta inválida.' using errcode = 'check_violation'; end if;
  v_ehcartao := v_conta.tipo = 'credito';
  if p_parcelas is null or p_parcelas < 1 then p_parcelas := 1; end if;

  -- soma dos itens recebidos (para valor do lançamento e rateio de frete/desconto)
  for linha in select * from jsonb_array_elements(p_itens) loop
    select * into ci from public.compra_itens where id = (linha->>'compra_item_id')::uuid;
    if not found or ci.compra_id <> c.id then raise exception 'Item do pedido inválido.' using errcode = 'check_violation'; end if;
    v_qtd := (linha->>'quantidade')::numeric;
    if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade recebida inválida em %.', ci.descricao using errcode = 'check_violation'; end if;
    if v_qtd > (ci.quantidade - ci.quantidade_recebida) then
      raise exception 'Recebendo % de %, mas restam %.', v_qtd, ci.descricao, (ci.quantidade - ci.quantidade_recebida) using errcode = 'check_violation';
    end if;
    v_soma_itens := v_soma_itens + v_qtd * ci.valor_unitario;
  end loop;

  -- proporção do frete/desconto sobre o que está sendo recebido agora
  select sum(quantidade * valor_unitario) into v_total_pedido from public.compra_itens where compra_id = c.id;
  v_frete_prop := case when v_total_pedido > 0 then round(c.valor_frete * (v_soma_itens / v_total_pedido), 2) else 0 end;
  v_desc_prop := case when v_total_pedido > 0 then round(c.valor_desconto * (v_soma_itens / v_total_pedido), 2) else 0 end;
  v_valor_lanc := round(v_soma_itens + v_frete_prop - v_desc_prop, 2);

  perform set_config('erp.motor', 'on', true);

  -- 1) cria o recebimento
  insert into public.compra_recebimentos (organizacao_id, compra_id, data, conferido_por, nota_numero, nota_chave, nota_valor, observacao)
  values (c.organizacao_id, c.id, coalesce(p_data, current_date), auth.uid(),
          nullif(btrim(coalesce(p_nota_numero, '')), ''), nullif(btrim(coalesce(p_nota_chave, '')), ''), p_nota_valor,
          nullif(btrim(coalesce(p_observacao, '')), ''))
  returning * into reb;

  -- 2) grava os itens recebidos, atualiza quantidade_recebida do pedido e dispara entrada_estoque quando cabe
  for linha in select * from jsonb_array_elements(p_itens) loop
    select * into ci from public.compra_itens where id = (linha->>'compra_item_id')::uuid;
    v_qtd := (linha->>'quantidade')::numeric;
    insert into public.compra_recebimento_itens (recebimento_id, compra_item_id, quantidade, numero_serie, observacao)
    values (reb.id, ci.id, v_qtd, nullif(btrim(coalesce(linha->>'numero_serie', '')), ''), nullif(btrim(coalesce(linha->>'observacao', '')), ''));
    update public.compra_itens set quantidade_recebida = quantidade_recebida + v_qtd where id = ci.id;
  end loop;

  -- 3) lançamento financeiro (à vista ou parcelado)
  v_categoria := p_categoria_padrao_id;
  if v_categoria is null then
    -- pega a primeira categoria informada nos itens; senão, padrão de despesa do negócio
    select ci2.categoria_id into v_categoria from public.compra_itens ci2
      where ci2.compra_id = c.id and ci2.categoria_id is not null order by ci2.id limit 1;
    if v_categoria is null then
      select n.categoria_despesa_id into v_categoria from public.negocios n where n.id = c.negocio_id;
    end if;
  end if;
  if v_categoria is null then raise exception 'Categoria de despesa não definida (informe categoria por item ou no negócio).' using errcode = 'check_violation'; end if;

  v_desc := 'Compra PED-' || lpad(c.numero::text, 4, '0');
  v_data_venc := coalesce(p_data, current_date);
  select * into v_lanc from public.criar_lancamento(
    'despesa', v_desc, v_valor_lanc, coalesce(p_data, current_date),
    v_data_venc,
    (case when v_ehcartao then null when p_pago then coalesce(p_data, current_date) else null end),
    p_conta_id, null, v_categoria,
    'Recebimento ' || to_char(coalesce(p_data, current_date), 'DD/MM/YYYY') || case when reb.nota_numero is not null then ' · NF ' || reb.nota_numero else '' end,
    c.negocio_id, c.fornecedor_id, null,
    (p_parcelas > 1), (case when p_parcelas > 1 then 'mensal' else null end), (case when p_parcelas > 1 then p_parcelas else null end), null
  );

  update public.compra_recebimentos set lancamento_id = v_lanc.id where id = reb.id
  returning * into reb;

  -- 4) para cada item destino=estoque com item_id, entrada_estoque
  for linha in select * from jsonb_array_elements(p_itens) loop
    select * into ci from public.compra_itens where id = (linha->>'compra_item_id')::uuid;
    v_qtd := (linha->>'quantidade')::numeric;
    if ci.destino = 'estoque' and ci.item_id is not null then
      perform public.entrada_estoque(ci.item_id, v_qtd, round(v_qtd * ci.valor_unitario, 2), coalesce(p_data, current_date), 'compra', v_lanc.id, 'Recebimento PED-' || lpad(c.numero::text, 4, '0'));
    end if;
  end loop;

  -- 5) atualizar status do pedido
  select coalesce(sum(quantidade_recebida), 0), coalesce(sum(quantidade), 0)
    into v_total_recebido, v_total_pedido
    from public.compra_itens where compra_id = c.id;
  update public.compras set status = (case when v_total_recebido >= v_total_pedido then 'recebido' else 'recebido_parcial' end)::public.status_pedido_compra where id = c.id;

  return reb;
end;
$$;

revoke all on function public.registrar_recebimento_compra(uuid, jsonb, date, text, text, numeric, text, uuid, boolean, integer, uuid) from public, anon;
grant execute on function public.registrar_recebimento_compra(uuid, jsonb, date, text, text, numeric, text, uuid, boolean, integer, uuid) to authenticated;

-- RLS + grants
alter table public.compra_recebimentos enable row level security;
alter table public.compra_recebimento_itens enable row level security;
create policy compra_receb_org on public.compra_recebimentos using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy compra_receb_itens_org on public.compra_recebimento_itens using (exists (select 1 from public.compra_recebimentos r where r.id = recebimento_id and r.organizacao_id in (select public.minhas_organizacoes()))) with check (exists (select 1 from public.compra_recebimentos r where r.id = recebimento_id and r.organizacao_id in (select public.minhas_organizacoes())));
revoke all on public.compra_recebimentos, public.compra_recebimento_itens from public, anon, authenticated;
grant select, insert, update on public.compra_recebimentos to authenticated;
grant select, insert on public.compra_recebimento_itens to authenticated;

-- -----------------------------------------------------------------------------
-- View para a Central de Relatórios: recebimentos com divergência
-- -----------------------------------------------------------------------------
create view public.vw_rel_compras_recebimentos with (security_invoker = true) as
select r.organizacao_id,
       r.id as recebimento_id,
       r.data,
       c.numero as pedido,
       n.nome as negocio,
       p.nome as fornecedor,
       r.nota_numero,
       r.nota_valor,
       (select sum(ri.quantidade * ci.valor_unitario)
          from public.compra_recebimento_itens ri
          join public.compra_itens ci on ci.id = ri.compra_item_id
         where ri.recebimento_id = r.id) as valor_recebido,
       case when r.nota_valor is null then 'sem nota'
            when abs(coalesce(r.nota_valor, 0) - coalesce((select sum(ri.quantidade * ci.valor_unitario)
                                                            from public.compra_recebimento_itens ri
                                                            join public.compra_itens ci on ci.id = ri.compra_item_id
                                                           where ri.recebimento_id = r.id), 0)) > 0.01 then 'divergente'
            else 'confere' end as situacao
  from public.compra_recebimentos r
  join public.compras c on c.id = r.compra_id
  join public.negocios n on n.id = c.negocio_id
  left join public.pessoas p on p.id = c.fornecedor_id;
grant select on public.vw_rel_compras_recebimentos to authenticated;
