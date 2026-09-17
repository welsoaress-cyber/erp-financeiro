-- Testes da migration 0093 (Compras: recebimento com nota + lançamento). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat_desp uuid; v_cat_rec uuid; v_forn uuid; v_estcat uuid; v_item uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'CO RECEB', 'co-receb') returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Banco Receb', 'dinheiro') returning id into v_conta;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Materiais Receb', 'despesa') returning id into v_cat_desp;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Rec Receb', 'receita') returning id into v_cat_rec;
  update public.negocios set conta_padrao_id = v_conta, categoria_receita_id = v_cat_rec, categoria_despesa_id = v_cat_desp where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Forn Receb') returning id into v_forn;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Cabos Receb') returning id into v_estcat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida)
    values (v_org, v_neg, v_estcat, 'CABO-R', 'Cabo Receb', 'metro') returning id into v_item;
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='co-receb') neg,
  (select id from public.pessoas where nome='Forn Receb') forn,
  (select id from public.contas where nome='Banco Receb') conta,
  (select id from public.categorias where nome='Materiais Receb') cat,
  (select id from public.estoque_itens where codigo='CABO-R') item;

-- prepara pedido aprovado com 2 itens (1000m estoque + 1 patrimônio)
do $$ declare v r%rowtype; req public.compra_requisicoes; c public.compras; begin
  select * into v from r;
  req := public.criar_requisicao_compra(v.neg, jsonb_build_array(
    jsonb_build_object('descricao', 'Cabo drop', 'quantidade', 1000, 'destino', 'estoque', 'item_id', v.item::text),
    jsonb_build_object('descricao', 'Roteador', 'quantidade', 1, 'destino', 'patrimonio')
  ), 'reposição');
  c := public.aprovar_requisicao_compra(req.id, v.forn, jsonb_build_array(
    jsonb_build_object('valor_unitario', 0.80, 'categoria_id', v.cat),
    jsonb_build_object('valor_unitario', 300, 'categoria_id', v.cat)
  ), current_date, current_date, '30 dias', 20, 0, null);
end $$;

-- T1: recebimento parcial (500m + 0 roteador) baixa pedido para recebido_parcial, cria despesa e entra no estoque
do $$ declare v r%rowtype; c_id uuid; ci_cabo uuid; reb public.compra_recebimentos; est_qtd numeric; begin
  select * into v from r;
  select id into c_id from public.compras where negocio_id = v.neg limit 1;
  select id into ci_cabo from public.compra_itens where compra_id = c_id and descricao = 'Cabo drop';
  reb := public.registrar_recebimento_compra(c_id,
    jsonb_build_array(jsonb_build_object('compra_item_id', ci_cabo::text, 'quantidade', 500)),
    current_date, 'NF-1', null, 400.00, 'parcial', v.conta, false, 1, v.cat);
  assert reb.lancamento_id is not null, 'T1 lançamento criado';
  assert (select status from public.compras where id = c_id) = 'recebido_parcial', 'T1 pedido parcial';
  assert (select quantidade_recebida from public.compra_itens where id = ci_cabo) = 500, 'T1 qtd recebida no item';
  select quantidade_atual into est_qtd from public.estoque_itens where id = v.item;
  assert est_qtd = 500, 'T1 estoque entrou: ' || est_qtd;
  -- valor do lançamento: 500*0.80 = 400 + frete rateado (20*400/1100)≈7.27, sem desconto → 407.27
  assert (select round(valor, 2) from public.lancamentos where id = reb.lancamento_id) between 407 and 408,
    'T1 valor lançamento: ' || (select valor from public.lancamentos where id = reb.lancamento_id);
  assert (select status from public.lancamentos where id = reb.lancamento_id) = 'previsto', 'T1 previsto (não pago)';
end $$;

-- T2: recebimento além do que resta falha
do $$ declare v r%rowtype; c_id uuid; ci_cabo uuid; begin
  select * into v from r;
  select id into c_id from public.compras where negocio_id = v.neg limit 1;
  select id into ci_cabo from public.compra_itens where compra_id = c_id and descricao = 'Cabo drop';
  begin
    perform public.registrar_recebimento_compra(c_id, jsonb_build_array(jsonb_build_object('compra_item_id', ci_cabo::text, 'quantidade', 600)), current_date, null, null, null, null, v.conta, false, 1, v.cat);
    raise exception 'T2 recebimento excedente deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: fechar recebimento (500m + 1 roteador) marca pedido como recebido; item patrimônio não entra no estoque
do $$ declare v r%rowtype; c_id uuid; ci_cabo uuid; ci_pat uuid; reb public.compra_recebimentos; est_qtd numeric; begin
  select * into v from r;
  select id into c_id from public.compras where negocio_id = v.neg limit 1;
  select id into ci_cabo from public.compra_itens where compra_id = c_id and descricao = 'Cabo drop';
  select id into ci_pat from public.compra_itens where compra_id = c_id and descricao = 'Roteador';
  reb := public.registrar_recebimento_compra(c_id,
    jsonb_build_array(
      jsonb_build_object('compra_item_id', ci_cabo::text, 'quantidade', 500),
      jsonb_build_object('compra_item_id', ci_pat::text, 'quantidade', 1, 'numero_serie', 'SN-001')
    ),
    current_date, 'NF-2', null, 712.73, null, v.conta, true, 1, v.cat);
  assert (select status from public.compras where id = c_id) = 'recebido', 'T3 pedido recebido';
  assert (select quantidade_atual from public.estoque_itens where id = v.item) = 1000, 'T3 estoque total = 1000';
  assert (select status from public.lancamentos where id = reb.lancamento_id) = 'efetivado', 'T3 pago → efetivado';
end $$;

-- T4: recebimento em pedido já recebido falha
do $$ declare v r%rowtype; c_id uuid; ci_cabo uuid; begin
  select * into v from r;
  select id into c_id from public.compras where negocio_id = v.neg limit 1;
  select id into ci_cabo from public.compra_itens where compra_id = c_id and descricao = 'Cabo drop';
  begin
    perform public.registrar_recebimento_compra(c_id, jsonb_build_array(jsonb_build_object('compra_item_id', ci_cabo::text, 'quantidade', 1)), current_date, null, null, null, null, v.conta, false, 1, v.cat);
    raise exception 'T4 recebimento em pedido concluído deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T5: recebimento imutável — UPDATE e DELETE bloqueados
do $$ declare v r%rowtype; reb_id uuid; begin
  select * into v from r;
  select id into reb_id from public.compra_recebimentos limit 1;
  perform set_config('erp.motor', '', true);
  begin
    update public.compra_recebimentos set observacao = 'x' where id = reb_id;
    raise exception 'T5 update deveria falhar';
  exception when check_violation or insufficient_privilege then null; end;
  begin
    delete from public.compra_recebimentos where id = reb_id;
    raise exception 'T5 delete deveria falhar';
  exception when check_violation or insufficient_privilege then null; end;
end $$;

rollback;
\echo OK
