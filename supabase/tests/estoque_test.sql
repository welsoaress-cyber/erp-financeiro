-- Testes da migration 0053 (estoque: itens, movimentações, custo médio). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'ESTOQUE TESTE', 'estoque-teste', true) returning id into v_neg;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Cabos Teste');
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='estoque-teste') neg,
  (select id from public.estoque_categorias where nome='Cabos Teste') cat;

-- T1: item nasce zerado; entrada calcula custo médio ponderado
do $$ declare v r%rowtype; v_item uuid; it public.estoque_itens; begin
  select * into v from r;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida, quantidade_minima)
  values (v.org, v.neg, v.cat, 'CABO-01', 'Cabo drop 1FO', 'metro', 100) returning id into v_item;
  begin
    insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, quantidade_atual)
    values (v.org, v.neg, v.cat, 'ERR-01', 'Nasce com saldo', 10);
    raise exception 'T1 item com saldo inicial direto deveria falhar';
  exception when check_violation then null; end;
  perform public.entrada_estoque(v_item, 1000, 800, current_date, 'compra');   -- 0,80/m
  perform public.entrada_estoque(v_item, 1000, 1200, current_date, 'compra');  -- 1,20/m → média 1,00
  select * into it from public.estoque_itens where id = v_item;
  assert it.quantidade_atual = 2000 and it.valor_custo = 1.0, 'T1 custo médio: ' || it.valor_custo || ' qtd ' || it.quantidade_atual;
end $$;

-- T2: saída usa custo médio, bloqueia acima do disponível; movimentação imutável
do $$ declare v r%rowtype; v_item uuid; m public.estoque_movimentacoes; it public.estoque_itens; begin
  select * into v from r;
  select id into v_item from public.estoque_itens where codigo = 'CABO-01';
  m := public.saida_estoque(v_item, 63.5, 'perda', current_date, null, null, 'teste');
  assert m.valor_total = 63.5, 'T2 valor da saída pelo custo médio: ' || m.valor_total;
  select * into it from public.estoque_itens where id = v_item;
  assert it.quantidade_atual = 1936.5, 'T2 quantidade após saída';
  begin
    perform public.saida_estoque(v_item, 99999, 'perda');
    raise exception 'T2 saída acima do estoque deveria falhar';
  exception when check_violation then null; end;
  perform set_config('erp.motor', '', true);
  begin
    update public.estoque_movimentacoes set quantidade = 1 where id = m.id;
    raise exception 'T2 movimentação editada deveria falhar';
  exception when check_violation or insufficient_privilege then null; end; -- sem grant de UPDATE, o banco nega antes do trigger
  begin
    update public.estoque_itens set quantidade_atual = 5 where id = v_item;
    raise exception 'T2 quantidade direta deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: ajuste de inventário define quantidade e registra o delta
do $$ declare v r%rowtype; v_item uuid; m public.estoque_movimentacoes; it public.estoque_itens; begin
  select * into v from r;
  select id into v_item from public.estoque_itens where codigo = 'CABO-01';
  m := public.ajuste_estoque(v_item, 1900, null, 'contagem física');
  assert m.tipo = 'ajuste' and m.quantidade = -36.5, 'T3 delta do ajuste: ' || m.quantidade;
  select * into it from public.estoque_itens where id = v_item;
  assert it.quantidade_atual = 1900, 'T3 quantidade ajustada';
end $$;

-- T4: devolução reentra pelo custo médio; saída com pessoa/contrato guarda o vínculo
do $$ declare v r%rowtype; v_item uuid; v_p uuid; m public.estoque_movimentacoes; begin
  select * into v from r;
  select id into v_item from public.estoque_itens where codigo = 'CABO-01';
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Estoque') returning id into v_p;
  m := public.saida_estoque(v_item, 10, 'instalacao', current_date, v_p, null, 'instalação teste');
  assert m.pessoa_id = v_p and m.origem = 'instalacao', 'T4 vínculo com o cliente';
  m := public.entrada_estoque(v_item, 10, 10, current_date, 'devolucao');
  assert m.origem = 'devolucao', 'T4 devolução registrada';
end $$;

rollback;
\echo OK
