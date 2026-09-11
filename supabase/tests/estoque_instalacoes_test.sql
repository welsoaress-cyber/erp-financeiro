-- Testes da migration 0054 (instalações, payback, relatórios). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_cat uuid; v_p uuid; v_plano uuid; v_conta uuid; v_cto uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'INST TESTE', 'inst-teste', true) returning id into v_neg;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Cabos Inst') returning id into v_cat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_cat, 'INST-CABO', 'Cabo drop', 'metro');
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_cat, 'INST-ONU', 'ONU', 'unidade');
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Cliente Instalação') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Fibra 100', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Inst', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.ctos (organizacao_id, negocio_id, codigo, latitude, longitude, quantidade_portas) values (v_org, v_neg, 'CTO-INST', -3.1, -60.0, 8) returning id into v_cto;
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='inst-teste') neg,
  (select id from public.estoque_itens where codigo='INST-CABO') cabo,
  (select id from public.estoque_itens where codigo='INST-ONU') onu,
  (select id from public.pessoas where nome='Cliente Instalação') pessoa,
  (select id from public.planos where nome='Fibra 100') plano,
  (select id from public.contas where nome='Caixa Inst') conta,
  (select id from public.ctos where codigo='CTO-INST') cto;

-- estoque inicial: cabo 1,00/m (1000 m), ONU 150,00 (5 un)
do $$ declare v r%rowtype; begin
  select * into v from r;
  perform public.entrada_estoque(v.cabo, 1000, 1000, current_date, 'compra');
  perform public.entrada_estoque(v.onu, 5, 750, current_date, 'compra');
end $$;

-- T1: instalação baixa os itens pelo custo médio, soma material + mão de obra e vincula a porta livre ao contrato
do $$ declare v r%rowtype; v_ct uuid; v_porta uuid; ins public.estoque_instalacoes; pt public.cto_portas; n_mov int; begin
  select * into v from r;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v.org, v.neg, v.pessoa, v.plano, 100, 'mensal', (current_date - interval '3 months')::date, 10, v.conta) returning id into v_ct;
  select id into v_porta from public.cto_portas where cto_id = v.cto and numero = 3;
  ins := public.registrar_instalacao(v.neg, v.pessoa, v_ct, v_porta, (current_date - interval '3 months')::date,
           jsonb_build_array(jsonb_build_object('item_id', v.cabo, 'quantidade', 80), jsonb_build_object('item_id', v.onu, 'quantidade', 1)),
           120, 'Técnico X', 'instalação teste');
  assert ins.custo_material = 230 and ins.mao_de_obra = 120 and ins.custo_total = 350, 'T1 custos: ' || ins.custo_material || ' / ' || ins.custo_total;
  select count(*) into n_mov from public.estoque_movimentacoes where instalacao_id = ins.id and origem = 'instalacao' and contrato_id = v_ct;
  assert n_mov = 2, 'T1 duas saídas vinculadas à instalação';
  assert (select quantidade_atual from public.estoque_itens where id = v.cabo) = 920, 'T1 cabo baixado';
  select * into pt from public.cto_portas where id = v_porta;
  assert pt.status = 'ocupada' and pt.pessoa_id = v.pessoa and pt.contrato_id = v_ct, 'T1 porta vinculada ao contrato';
  begin
    update public.estoque_instalacoes set mao_de_obra = 1 where id = ins.id;
    raise exception 'T1 instalação editada deveria falhar';
  exception when check_violation or insufficient_privilege then null; end;
  begin
    insert into public.estoque_instalacoes (organizacao_id, negocio_id, pessoa_id) values (v.org, v.neg, v.pessoa);
    raise exception 'T1 insert direto deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

-- T2: bloqueios — estoque insuficiente (nada gravado), contrato de outro cliente, porta ocupada por outro
do $$ declare v r%rowtype; v_ct uuid; v_p2 uuid; v_ct2 uuid; v_porta uuid; n int; begin
  select * into v from r;
  select id into v_ct from public.contratos where pessoa_id = v.pessoa and negocio_id = v.neg;
  begin
    perform public.registrar_instalacao(v.neg, v.pessoa, v_ct, null, current_date, jsonb_build_array(jsonb_build_object('item_id', v.onu, 'quantidade', 99)), 0);
    raise exception 'T2 saída acima do estoque deveria falhar';
  exception when check_violation then null; end;
  select count(*) into n from public.estoque_instalacoes where pessoa_id = v.pessoa;
  assert n = 1, 'T2 instalação falha não grava nada';
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Outro Cliente') returning id into v_p2;
  begin
    perform public.registrar_instalacao(v.neg, v_p2, v_ct, null, current_date, '[]'::jsonb, 50);
    raise exception 'T2 contrato de outro cliente deveria falhar';
  exception when check_violation then null; end;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v.org, v.neg, v_p2, v.plano, 100, 'mensal', current_date, 10, v.conta) returning id into v_ct2;
  select id into v_porta from public.cto_portas where cto_id = v.cto and numero = 3;
  begin
    perform public.registrar_instalacao(v.neg, v_p2, v_ct2, v_porta, current_date, '[]'::jsonb, 50);
    raise exception 'T2 porta ocupada por outro deveria falhar';
  exception when check_violation then null; end;
  -- só mão de obra, sem itens e sem porta: permitido
  perform public.registrar_instalacao(v.neg, v_p2, v_ct2, null, current_date, '[]'::jsonb, 50);
end $$;

-- T3: payback — estimado = ceil(350 / 100) = 4 meses; real quando as receitas efetivadas acumulam 350
do $$ declare v r%rowtype; v_ct uuid; pb record; i int; d date; begin
  select * into v from r;
  select id into v_ct from public.contratos where pessoa_id = v.pessoa and negocio_id = v.neg;
  select * into pb from public.vw_payback_contrato where contrato_id = v_ct;
  assert pb.custo_instalacao = 350 and pb.mensalidade = 100 and pb.payback_estimado_meses = 4 and pb.recebido = 0 and pb.data_payback_real is null, 'T3 estimado: ' || pb.payback_estimado_meses;
  for i in 0..3 loop
    d := (current_date - interval '3 months' + make_interval(months => i))::date;
    perform public.criar_lancamento('receita', 'Mensalidade ' || i, 100, d, d, d,
      v.conta, null, (select id from public.categorias where tipo = 'receita' limit 1), null, v.neg, v.pessoa, v_ct);
  end loop;
  select * into pb from public.vw_payback_contrato where contrato_id = v_ct;
  assert pb.recebido = 400 and pb.data_payback_real = current_date, 'T3 real: ' || pb.recebido || ' em ' || coalesce(pb.data_payback_real::text, 'null');
  assert pb.payback_real_meses = 3, 'T3 meses reais (da 1ª instalação ao pagamento): ' || pb.payback_real_meses;
end $$;

-- T4: relatórios — consumo mensal por origem e por item
do $$ declare v r%rowtype; c record; begin
  select * into v from r;
  select * into c from public.vw_estoque_consumo_mensal where negocio_id = v.neg and origem = 'instalacao' and mes = to_char(current_date - interval '3 months', 'YYYY-MM');
  assert c.movimentacoes = 2 and c.valor_total = 230, 'T4 consumo mensal instalação: ' || c.valor_total;
  select * into c from public.vw_estoque_consumo_item where negocio_id = v.neg and item_id = v.cabo;
  assert c.quantidade = 80 and c.valor_total = 80, 'T4 consumo do cabo: ' || c.quantidade;
end $$;

rollback;
\echo OK
