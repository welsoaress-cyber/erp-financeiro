-- Testes das migrations 0130 (recebimento sem item_id cria o item em estoque_itens sozinho)
-- e 0131 (recebimento propaga compra_itens.contrato_id pro lançamento). Saída "OK".
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

-- T2 (0131): todos os itens do recebimento com o MESMO contrato → lançamento nasce vinculado
do $$ declare v r%rowtype; v_cliente uuid; v_plano uuid; v_ct uuid; req public.compra_requisicoes; c public.compras; ci_id uuid; reb public.compra_recebimentos; begin
  select * into v from r;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente AutoItem') returning id into v_cliente;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v.org, v.neg, 'Plano AutoItem', 100, 'mensal') returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, tipo_financeiro)
    values (v.org, v.neg, v_cliente, v_plano, 100, 'mensal', current_date, 10, 'receita') returning id into v_ct;

  req := public.criar_requisicao_compra(v.neg, jsonb_build_array(
    jsonb_build_object('descricao', 'Roteador pro cliente', 'quantidade', 1, 'destino', 'comodato')
  ), 'teste vínculo contrato');
  c := public.aprovar_requisicao_compra(req.id, v.forn, jsonb_build_array(
    jsonb_build_object('valor_unitario', 80.00, 'categoria_id', v.cat, 'contrato_id', v_ct::text)
  ), current_date, current_date, 'à vista', 0, 0, null);
  select id into ci_id from public.compra_itens where compra_id = c.id;
  assert (select contrato_id from public.compra_itens where id = ci_id) = v_ct, 'T2 contrato_id gravado na aprovação';

  reb := public.registrar_recebimento_compra(c.id,
    jsonb_build_array(jsonb_build_object('compra_item_id', ci_id::text, 'quantidade', 1)),
    current_date, 'NF-RT', null, 80.00, null, v.conta, true, 1, v.cat);
  assert (select contrato_id from public.lancamentos where id = reb.lancamento_id) = v_ct, 'T2 lançamento vinculado ao contrato sozinho';
end $$;

-- T3 (0131): recebimento mistura item com contrato e item sem contrato → lançamento fica sem vínculo (não atribui errado)
do $$ declare v r%rowtype; v_cliente uuid; v_plano uuid; v_ct uuid; req public.compra_requisicoes; c public.compras; ci1 uuid; ci2 uuid; reb public.compra_recebimentos; begin
  select * into v from r;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente AutoItem 2') returning id into v_cliente;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v.org, v.neg, 'Plano AutoItem 2', 100, 'mensal') returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, tipo_financeiro)
    values (v.org, v.neg, v_cliente, v_plano, 100, 'mensal', current_date, 10, 'receita') returning id into v_ct;

  req := public.criar_requisicao_compra(v.neg, jsonb_build_array(
    jsonb_build_object('descricao', 'Item do cliente', 'quantidade', 1, 'destino', 'comodato'),
    jsonb_build_object('descricao', 'Item de estoque geral', 'quantidade', 1, 'destino', 'estoque')
  ), 'teste vínculo misto');
  c := public.aprovar_requisicao_compra(req.id, v.forn, jsonb_build_array(
    jsonb_build_object('valor_unitario', 50.00, 'categoria_id', v.cat, 'contrato_id', v_ct::text),
    jsonb_build_object('valor_unitario', 50.00, 'categoria_id', v.cat)
  ), current_date, current_date, 'à vista', 0, 0, null);
  select id into ci1 from public.compra_itens where compra_id = c.id and descricao = 'Item do cliente';
  select id into ci2 from public.compra_itens where compra_id = c.id and descricao = 'Item de estoque geral';

  reb := public.registrar_recebimento_compra(c.id,
    jsonb_build_array(jsonb_build_object('compra_item_id', ci1::text, 'quantidade', 1), jsonb_build_object('compra_item_id', ci2::text, 'quantidade', 1)),
    current_date, 'NF-MISTO', null, 100.00, null, v.conta, true, 1, v.cat);
  assert (select contrato_id from public.lancamentos where id = reb.lancamento_id) is null, 'T3 lançamento misto fica sem vínculo';
end $$;

rollback;
\echo OK
