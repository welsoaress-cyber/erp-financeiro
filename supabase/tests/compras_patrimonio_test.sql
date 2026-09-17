-- Testes da migration 0094 (Compras: recebimento com destino patrimônio). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat_desp uuid; v_cat_rec uuid; v_forn uuid; v_estcat uuid; v_item uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'CO PAT', 'co-pat') returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Banco Pat', 'dinheiro') returning id into v_conta;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Materiais Pat', 'despesa') returning id into v_cat_desp;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Rec Pat', 'receita') returning id into v_cat_rec;
  update public.negocios set conta_padrao_id = v_conta, categoria_receita_id = v_cat_rec, categoria_despesa_id = v_cat_desp where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Forn Pat') returning id into v_forn;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Cabos Pat') returning id into v_estcat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida)
    values (v_org, v_neg, v_estcat, 'CABO-P', 'Cabo Pat', 'metro') returning id into v_item;
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='co-pat') neg,
  (select id from public.pessoas where nome='Forn Pat') forn,
  (select id from public.contas where nome='Banco Pat') conta,
  (select id from public.categorias where nome='Materiais Pat') cat,
  (select id from public.estoque_itens where codigo='CABO-P') item;

-- Pedido com 3 patrimônios + comodato tratado como estoque
do $$ declare v r%rowtype; req public.compra_requisicoes; c public.compras; begin
  select * into v from r;
  req := public.criar_requisicao_compra(v.neg, jsonb_build_array(
    jsonb_build_object('descricao', 'Fusionadora XPTO', 'quantidade', 3, 'destino', 'patrimonio'),
    jsonb_build_object('descricao', 'ONU comodato', 'quantidade', 2, 'destino', 'comodato', 'item_id', v.item::text)
  ), 'ferramentas + onus');
  c := public.aprovar_requisicao_compra(req.id, v.forn, jsonb_build_array(
    jsonb_build_object('valor_unitario', 5000, 'categoria_id', v.cat),
    jsonb_build_object('valor_unitario', 100, 'categoria_id', v.cat)
  ), current_date, current_date, 'à vista', 0, 0, null);
end $$;

-- T1: receber recebe todo o pedido; cria 3 patrimônios (com PAT-nnn) e comodato entra em estoque_itens
do $$ declare v r%rowtype; c_id uuid; ci_pat uuid; ci_com uuid; reb public.compra_recebimentos; pats int; est numeric; begin
  select * into v from r;
  select id into c_id from public.compras where negocio_id = v.neg limit 1;
  select id into ci_pat from public.compra_itens where compra_id = c_id and descricao = 'Fusionadora XPTO';
  select id into ci_com from public.compra_itens where compra_id = c_id and descricao = 'ONU comodato';
  reb := public.registrar_recebimento_compra(c_id,
    jsonb_build_array(
      jsonb_build_object('compra_item_id', ci_pat::text, 'quantidade', 3, 'numero_serie', 'FUS-001'),
      jsonb_build_object('compra_item_id', ci_com::text, 'quantidade', 2)
    ), current_date, 'NF-P1', null, 15200.00, null, v.conta, true, 1, v.cat);
  select count(*) into pats from public.patrimonios where lancamento_id = reb.lancamento_id;
  assert pats = 3, 'T1 três patrimônios criados: ' || pats;
  assert (select count(*) from public.patrimonios where lancamento_id = reb.lancamento_id and numero_serie = 'FUS-001') = 1, 'T1 apenas o 1º recebe a série';
  select quantidade_atual into est from public.estoque_itens where id = v.item;
  assert est = 2, 'T1 comodato entrou no estoque: ' || est;
  assert (select status from public.compras where id = c_id) = 'recebido', 'T1 pedido concluído';
  assert (select nome from public.patrimonios where lancamento_id = reb.lancamento_id limit 1) = 'Fusionadora XPTO', 'T1 nome herdado';
  assert (select valor_aquisicao from public.patrimonios where lancamento_id = reb.lancamento_id limit 1) = 5000, 'T1 valor aquisição';
end $$;

rollback;
\echo OK
