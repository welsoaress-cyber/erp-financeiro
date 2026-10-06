-- =============================================================================
-- 0130 · Recebimento com destino estoque/comodato sem item_id cria o item sozinho
-- =============================================================================
-- Bug real: requisição com item "novo" (descrição livre, sem escolher um item
-- já cadastrado) sempre existiu como opção no formulário, mas o recebimento
-- (0093/0094) só dava entrada em estoque quando ci.item_id já vinha preenchido
-- — se não vinha, a despesa era lançada e o material "sumia": pagou, não
-- entrou em lugar nenhum. destino='patrimonio' já resolvia isso (cria o bem
-- sozinho, 0094); agora estoque/comodato seguem o mesmo princípio: ausência
-- de item_id no recebimento cria o item em estoque_itens (categoria
-- "Equipamentos" do negócio, ou a primeira ativa que existir) e vincula o
-- compra_itens a ele, antes da entrada_estoque de sempre.
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
  v_item_id uuid; v_cat_estoque uuid; v_codigo text; v_n int;
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
  --           sem item_id, cria o item sozinho antes (categoria "Equipamentos" ou a primeira ativa do negócio);
  --           patrimonio → cria bem individual por unidade (numero_serie do recebimento);
  --           despesa/serviço → só o lançamento (já feito).
  select nome into v_neg_nome from public.negocios where id = c.negocio_id;
  for linha in select * from jsonb_array_elements(p_itens) loop
    select * into ci from public.compra_itens where id = (linha->>'compra_item_id')::uuid;
    v_qtd := (linha->>'quantidade')::numeric;
    if ci.destino in ('estoque', 'comodato') then
      v_item_id := ci.item_id;
      if v_item_id is null then
        select id into v_cat_estoque from public.estoque_categorias
          where negocio_id = c.negocio_id and ativo
          order by (nome = 'Equipamentos') desc, nome
          limit 1;
        if v_cat_estoque is null then
          raise exception 'Sem categoria de estoque ativa em %. Crie uma em Estoque → Categorias antes de receber item novo.', coalesce(v_neg_nome, 'negócio') using errcode = 'check_violation';
        end if;
        v_n := 0;
        loop
          v_n := v_n + 1;
          v_codigo := 'ITM' || lpad(v_n::text, 4, '0');
          exit when not exists (select 1 from public.estoque_itens where organizacao_id = c.organizacao_id and codigo = v_codigo);
        end loop;
        insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida)
        values (c.organizacao_id, c.negocio_id, v_cat_estoque, v_codigo, left(ci.descricao, 80), 'unidade')
        returning id into v_item_id;
        update public.compra_itens set item_id = v_item_id where id = ci.id;
      end if;
      perform public.entrada_estoque(v_item_id, v_qtd, round(v_qtd * ci.valor_unitario, 2), coalesce(p_data, current_date), 'compra', v_lanc.id, 'Recebimento PED-' || lpad(c.numero::text, 4, '0'));
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

-- -----------------------------------------------------------------------------
-- Backfill: recebimentos já registrados antes desta migration, com destino
-- estoque/comodato e item_id nunca preenchido, ficaram sem entrada em
-- estoque_itens (a despesa foi lançada, o material "sumiu"). Cria o item e
-- repõe a entrada de cada recebimento já feito, na ordem em que aconteceram,
-- preservando o custo médio ponderado histórico.
-- -----------------------------------------------------------------------------
-- Nota: roda como dono da migration (SQL Editor é 'postgres', sem auth.uid() de usuário
-- logado) — por isso NÃO chama entrada_estoque (exige exigir_membro/auth.uid()) e replica
-- a mesma lógica (custo médio ponderado) direto nas tabelas.
do $$
declare
  ci record; ri record; c public.compras%rowtype;
  v_cat_estoque uuid; v_codigo text; v_n int; v_item_id uuid;
  v_qtd_atual numeric; v_custo_atual numeric; v_valor_total numeric; v_unit numeric;
begin
  perform set_config('erp.motor', 'on', true);
  for ci in
    select * from public.compra_itens
    where destino in ('estoque', 'comodato') and item_id is null and quantidade_recebida > 0
  loop
    select * into c from public.compras where id = ci.compra_id;
    select id into v_cat_estoque from public.estoque_categorias
      where negocio_id = c.negocio_id and ativo
      order by (nome = 'Equipamentos') desc, nome
      limit 1;
    if v_cat_estoque is null then continue; end if; -- sem categoria: fica para conserto manual, não trava a migration
    v_n := 0;
    loop
      v_n := v_n + 1;
      v_codigo := 'ITM' || lpad(v_n::text, 4, '0');
      exit when not exists (select 1 from public.estoque_itens where organizacao_id = c.organizacao_id and codigo = v_codigo);
    end loop;
    insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida)
    values (c.organizacao_id, c.negocio_id, v_cat_estoque, v_codigo, left(ci.descricao, 80), 'unidade')
    returning id into v_item_id;
    update public.compra_itens set item_id = v_item_id where id = ci.id;
    for ri in
      select cri.*, cr.data, cr.lancamento_id from public.compra_recebimento_itens cri
      join public.compra_recebimentos cr on cr.id = cri.recebimento_id
      where cri.compra_item_id = ci.id
      order by cr.data, cri.id
    loop
      v_valor_total := round(ri.quantidade * ci.valor_unitario, 2);
      v_unit := round(v_valor_total / ri.quantidade, 4);
      select quantidade_atual, valor_custo into v_qtd_atual, v_custo_atual from public.estoque_itens where id = v_item_id;
      update public.estoque_itens
         set valor_custo = case when v_qtd_atual + ri.quantidade > 0
                                 then round((v_qtd_atual * v_custo_atual + v_valor_total) / (v_qtd_atual + ri.quantidade), 4)
                                 else v_custo_atual end,
             quantidade_atual = v_qtd_atual + ri.quantidade
       where id = v_item_id;
      insert into public.estoque_movimentacoes (organizacao_id, negocio_id, item_id, tipo, origem, quantidade, valor_unitario, valor_total, data, lancamento_id, observacao)
      values (c.organizacao_id, c.negocio_id, v_item_id, 'entrada', 'compra', ri.quantidade, v_unit, v_valor_total, ri.data, ri.lancamento_id, 'Backfill (0130) · recebimento sem item vinculado');
    end loop;
  end loop;
end $$;
