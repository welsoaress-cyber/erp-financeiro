-- =============================================================================
-- 0094 · Etapa 55C — Compras: destino Patrimônio no recebimento
-- =============================================================================
-- No recebimento (0093), item com destino='patrimonio' passa a criar um bem
-- individual em `patrimonios` por unidade recebida (numero_serie herdado do
-- recebimento; a localização começa como o nome do negócio + PED-NNNN e pode
-- ser editada depois). Comodato continua tratado como estoque (o material
-- entra em `estoque_itens` normalmente; só vira comodato quando alocado a um
-- cliente pelo módulo Estoque, mais tarde). Despesa e Serviço não geram nada
-- físico — só o lançamento financeiro, como já em 55B.
-- =============================================================================

create or replace function public.registrar_recebimento_compra(
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
  linha jsonb; ci public.compra_itens%rowtype; v_qtd numeric;
  v_total_pedido numeric := 0; v_total_recebido numeric := 0;
  v_valor_lanc numeric := 0; v_categoria uuid; v_desc text;
  v_lanc public.lancamentos%rowtype;
  v_frete_prop numeric; v_desc_prop numeric; v_soma_itens numeric := 0;
  v_data_venc date; v_conta public.contas%rowtype; v_ehcartao boolean := false;
  v_neg_nome text; v_i int;
  v_serie text;
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

  select sum(quantidade * valor_unitario) into v_total_pedido from public.compra_itens where compra_id = c.id;
  v_frete_prop := case when v_total_pedido > 0 then round(c.valor_frete * (v_soma_itens / v_total_pedido), 2) else 0 end;
  v_desc_prop := case when v_total_pedido > 0 then round(c.valor_desconto * (v_soma_itens / v_total_pedido), 2) else 0 end;
  v_valor_lanc := round(v_soma_itens + v_frete_prop - v_desc_prop, 2);

  perform set_config('erp.motor', 'on', true);

  insert into public.compra_recebimentos (organizacao_id, compra_id, data, conferido_por, nota_numero, nota_chave, nota_valor, observacao)
  values (c.organizacao_id, c.id, coalesce(p_data, current_date), auth.uid(),
          nullif(btrim(coalesce(p_nota_numero, '')), ''), nullif(btrim(coalesce(p_nota_chave, '')), ''), p_nota_valor,
          nullif(btrim(coalesce(p_observacao, '')), ''))
  returning * into reb;

  for linha in select * from jsonb_array_elements(p_itens) loop
    select * into ci from public.compra_itens where id = (linha->>'compra_item_id')::uuid;
    v_qtd := (linha->>'quantidade')::numeric;
    insert into public.compra_recebimento_itens (recebimento_id, compra_item_id, quantidade, numero_serie, observacao)
    values (reb.id, ci.id, v_qtd, nullif(btrim(coalesce(linha->>'numero_serie', '')), ''), nullif(btrim(coalesce(linha->>'observacao', '')), ''));
    update public.compra_itens set quantidade_recebida = quantidade_recebida + v_qtd where id = ci.id;
  end loop;

  v_categoria := p_categoria_padrao_id;
  if v_categoria is null then
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

  -- destinos: estoque/comodato → entrada_estoque (comodato só vira comodato quando alocado ao cliente depois);
  --           patrimonio → cria bem individual por unidade (numero_serie do recebimento);
  --           despesa/serviço → só o lançamento (já feito).
  select nome into v_neg_nome from public.negocios where id = c.negocio_id;
  for linha in select * from jsonb_array_elements(p_itens) loop
    select * into ci from public.compra_itens where id = (linha->>'compra_item_id')::uuid;
    v_qtd := (linha->>'quantidade')::numeric;
    if ci.destino in ('estoque', 'comodato') and ci.item_id is not null then
      perform public.entrada_estoque(ci.item_id, v_qtd, round(v_qtd * ci.valor_unitario, 2), coalesce(p_data, current_date), 'compra', v_lanc.id, 'Recebimento PED-' || lpad(c.numero::text, 4, '0'));
    elsif ci.destino = 'patrimonio' then
      v_serie := nullif(btrim(coalesce(linha->>'numero_serie', '')), '');
      for v_i in 1 .. floor(v_qtd)::int loop
        insert into public.patrimonios (organizacao_id, negocio_id, numero, nome, numero_serie, valor_aquisicao, data_aquisicao, nota_fiscal, localizacao, lancamento_id, observacao)
        values (c.organizacao_id, c.negocio_id, 0, ci.descricao,
                case when v_i = 1 then v_serie else null end,
                round(ci.valor_unitario, 2), coalesce(p_data, current_date),
                reb.nota_numero, coalesce(v_neg_nome, 'Estoque') || ' · PED-' || lpad(c.numero::text, 4, '0'),
                v_lanc.id, 'Aquisição via ' || v_desc);
      end loop;
    end if;
  end loop;

  select coalesce(sum(quantidade_recebida), 0), coalesce(sum(quantidade), 0)
    into v_total_recebido, v_total_pedido
    from public.compra_itens where compra_id = c.id;
  update public.compras set status = (case when v_total_recebido >= v_total_pedido then 'recebido' else 'recebido_parcial' end)::public.status_pedido_compra where id = c.id;

  return reb;
end;
$$;
