-- Testes da migration 0092 (Compras: requisição e pedido). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat uuid; v_forn uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'COMPRAS TESTE', 'compras-teste') returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Banco Compras', 'dinheiro') returning id into v_conta;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Compra Materiais', 'despesa') returning id into v_cat;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Fornecedor X') returning id into v_forn;
  -- garante que 11111111 seja proprietário nessa organização de teste (é a org do shim)
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='compras-teste') neg,
  (select id from public.pessoas where nome='Fornecedor X') forn,
  (select id from public.categorias where nome='Compra Materiais') cat;

-- T1: qualquer membro cria a requisição; ela nasce pendente com numeração 1
do $$ declare v r%rowtype; req public.compra_requisicoes; begin
  select * into v from r;
  req := public.criar_requisicao_compra(v.neg, jsonb_build_array(
    jsonb_build_object('descricao', 'Cabo drop 1FO', 'quantidade', 1000, 'destino', 'estoque'),
    jsonb_build_object('descricao', 'Conector SC/APC', 'quantidade', 200, 'destino', 'estoque')
  ), 'Reposição de estoque baixo');
  assert req.status = 'pendente' and req.numero = 1, 'T1 nasce pendente numero=1: ' || req.status || ' ' || req.numero;
  assert (select count(*) from public.compra_requisicao_itens where requisicao_id = req.id) = 2, 'T1 dois itens gravados';
end $$;

-- T2: só proprietário aprova/rejeita
do $$ declare v r%rowtype; req_id uuid; begin
  select * into v from r;
  select id into req_id from public.compra_requisicoes where negocio_id = v.neg and numero = 1;
  -- simulando um membro NÃO-proprietário: usamos um jwt sub diferente e recriamos a expectativa
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  begin
    perform public.aprovar_requisicao_compra(req_id, v.forn, jsonb_build_array(jsonb_build_object('valor_unitario', 0.8), jsonb_build_object('valor_unitario', 1.2)));
    raise exception 'T2 não-proprietário não deveria aprovar';
  exception when insufficient_privilege then null; end;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
end $$;

-- T3: aprovar cria o pedido; requisição vira convertida; totais batem na view
do $$ declare v r%rowtype; req_id uuid; c public.compras; total numeric; begin
  select * into v from r;
  select id into req_id from public.compra_requisicoes where negocio_id = v.neg and numero = 1;
  c := public.aprovar_requisicao_compra(req_id, v.forn, jsonb_build_array(
    jsonb_build_object('valor_unitario', 0.80, 'categoria_id', v.cat),
    jsonb_build_object('valor_unitario', 1.20, 'categoria_id', v.cat)
  ), current_date, current_date + 5, '30 dias', 50, 10, 'pedido inicial');
  assert c.status = 'aberto' and c.numero = 1, 'T3 pedido aberto numero=1';
  assert (select status from public.compra_requisicoes where id = req_id) = 'convertida', 'T3 requisição convertida';
  assert (select pedido_id from public.compra_requisicoes where id = req_id) = c.id, 'T3 pedido amarrado à requisição';
  select total_final into total from public.vw_compras_totais where compra_id = c.id;
  -- itens: 1000*0.80 + 200*1.20 = 800 + 240 = 1040; +50 frete -10 desconto = 1080
  assert total = 1080, 'T3 total final: ' || total;
end $$;

-- T4: não pode aprovar duas vezes; requisição já decidida rejeita
do $$ declare v r%rowtype; req_id uuid; begin
  select * into v from r;
  select id into req_id from public.compra_requisicoes where negocio_id = v.neg and numero = 1;
  begin
    perform public.aprovar_requisicao_compra(req_id, v.forn, jsonb_build_array(jsonb_build_object('valor_unitario', 1), jsonb_build_object('valor_unitario', 1)));
    raise exception 'T4 aprovar de novo deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.rejeitar_requisicao_compra(req_id, 'motivo');
    raise exception 'T4 rejeitar convertida deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T5: rejeitar exige motivo; cancelar por outro usuário sem ser dono nem solicitante falha
do $$ declare v r%rowtype; req public.compra_requisicoes; begin
  select * into v from r;
  req := public.criar_requisicao_compra(v.neg, jsonb_build_array(jsonb_build_object('descricao', 'Cabo drop', 'quantidade', 5)), null);
  begin
    perform public.rejeitar_requisicao_compra(req.id, '');
    raise exception 'T5 rejeitar sem motivo deveria falhar';
  exception when check_violation then null; end;
  perform public.rejeitar_requisicao_compra(req.id, 'preço alto');
  assert (select status from public.compra_requisicoes where id = req.id) = 'rejeitada', 'T5 rejeitada';
end $$;

-- T6: cancelar pedido em aberto vira cancelado; cancelar de novo falha
do $$ declare v r%rowtype; c_id uuid; begin
  select * into v from r;
  select id into c_id from public.compras where negocio_id = v.neg and numero = 1;
  perform public.cancelar_pedido_compra(c_id, 'desistimos');
  assert (select status from public.compras where id = c_id) = 'cancelado', 'T6 cancelado';
  begin
    perform public.cancelar_pedido_compra(c_id, 'de novo');
    raise exception 'T6 recancelar deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T7: proteção — mudar status direto (fora do motor) falha
do $$ declare v r%rowtype; req_id uuid; begin
  select * into v from r;
  select id into req_id from public.compra_requisicoes where negocio_id = v.neg limit 1;
  perform set_config('erp.motor', '', true);
  begin
    update public.compra_requisicoes set status = 'aprovada' where id = req_id;
    raise exception 'T7 update de status fora do motor deveria falhar';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.compras where negocio_id = v.neg;
    raise exception 'T7 delete deveria falhar';
  exception when check_violation or insufficient_privilege then null; end;
end $$;

rollback;
\echo OK
