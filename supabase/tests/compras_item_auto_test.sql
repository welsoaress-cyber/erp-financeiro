-- Testes da migration 0130 (recebimento sem item_id cria o item em estoque_itens sozinho). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat_desp uuid; v_forn uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'CO AUTOITEM', 'co-autoitem') returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Banco AutoItem', 'dinheiro') returning id into v_conta;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Despesa AutoItem', 'despesa') returning id into v_cat_desp;
  update public.negocios set conta_padrao_id = v_conta, categoria_despesa_id = v_cat_desp where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Forn AutoItem') returning id into v_forn;
  -- 0053 só seedou categorias padrão (Cabos, Conectores, Equipamentos, ...) para os negócios que já existiam
  -- naquele momento; negócio criado agora (como este) precisa da sua própria, igual já acontece na prática.
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Equipamentos');
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='co-autoitem') neg,
  (select id from public.pessoas where nome='Forn AutoItem') forn,
  (select id from public.contas where nome='Banco AutoItem') conta,
  (select id from public.categorias where nome='Despesa AutoItem') cat;

-- requisição com item NOVO (sem item_id), destino estoque
do $$ declare v r%rowtype; req public.compra_requisicoes; c public.compras; begin
  select * into v from r;
  req := public.criar_requisicao_compra(v.neg, jsonb_build_array(
    jsonb_build_object('descricao', 'Câmera IP Intelbras', 'quantidade', 1, 'destino', 'estoque')
  ), 'teste sva câmera');
  c := public.aprovar_requisicao_compra(req.id, v.forn, jsonb_build_array(
    jsonb_build_object('valor_unitario', 150.00, 'categoria_id', v.cat)
  ), current_date, current_date, 'à vista', 0, 0, null);
end $$;

-- T1: recebimento cria o item em estoque_itens sozinho, vincula compra_itens.item_id e dá entrada
do $$ declare v r%rowtype; c_id uuid; ci_id uuid; reb public.compra_recebimentos; v_item_id uuid; begin
  select * into v from r;
  select id into c_id from public.compras where negocio_id = v.neg limit 1;
  select id into ci_id from public.compra_itens where compra_id = c_id and descricao = 'Câmera IP Intelbras';
  assert (select item_id from public.compra_itens where id = ci_id) is null, 'T1 item_id começa nulo';
  reb := public.registrar_recebimento_compra(c_id,
    jsonb_build_array(jsonb_build_object('compra_item_id', ci_id::text, 'quantidade', 1, 'numero_serie', 'SN-CAM-001')),
    current_date, 'NF-CAM', null, 150.00, null, v.conta, true, 1, v.cat);
  select item_id into v_item_id from public.compra_itens where id = ci_id;
  assert v_item_id is not null, 'T1 item_id preenchido depois do recebimento';
  assert (select nome from public.estoque_itens where id = v_item_id) = 'Câmera IP Intelbras', 'T1 nome do item criado';
  assert (select quantidade_atual from public.estoque_itens where id = v_item_id) = 1, 'T1 quantidade entrou';
  assert (select valor_custo from public.estoque_itens where id = v_item_id) = 150, 'T1 custo médio = valor pago';
  assert (select status from public.lancamentos where id = reb.lancamento_id) = 'efetivado', 'T1 lançamento pago';
end $$;

rollback;
\echo OK
