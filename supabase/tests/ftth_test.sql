-- Testes da migration 0047 (FTTH: CTOs, portas, histórico). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

-- cenário: negócio, plano, 2 clientes com contrato ativo e 1 contrato encerrado
do $$ declare v_org uuid; v_neg uuid; v_plano uuid; v_p1 uuid; v_p2 uuid; v_p3 uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'FTTH TESTE', 'ftth-teste') returning id into v_neg;
  update public.negocios set conta_padrao_id = (select id from public.contas where organizacao_id = v_org limit 1),
    categoria_receita_id = (select id from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v_org, v_neg, 'Fibra Teste', 60) returning id into v_plano;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Cliente Ftth Um') returning id into v_p1;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Cliente Ftth Dois') returning id into v_p2;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Cliente Ftth Tres') returning id into v_p3;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, faturamento_automatico)
  values (v_org, v_neg, v_p1, v_plano, 60, 'mensal', current_date, 10, false),
         (v_org, v_neg, v_p2, v_plano, 60, 'mensal', current_date, 10, false),
         (v_org, v_neg, v_p3, v_plano, 60, 'mensal', current_date, 10, false);
  update public.contratos set status = 'encerrado', data_fim = current_date where pessoa_id = v_p3;
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='ftth-teste') neg,
  (select id from public.pessoas where nome='Cliente Ftth Um') p1,
  (select id from public.pessoas where nome='Cliente Ftth Dois') p2,
  (select id from public.pessoas where nome='Cliente Ftth Tres') p3,
  (select c.id from public.contratos c join public.pessoas p on p.id=c.pessoa_id where p.nome='Cliente Ftth Um') ct1,
  (select c.id from public.contratos c join public.pessoas p on p.id=c.pessoa_id where p.nome='Cliente Ftth Dois') ct2,
  (select c.id from public.contratos c join public.pessoas p on p.id=c.pessoa_id where p.nome='Cliente Ftth Tres') ct3;

-- T1: criar CTO gera as portas; aumentar quantidade gera mais; reduzir com ocupada falha
do $$ declare v r%rowtype; v_cto uuid; begin
  select * into v from r;
  insert into public.ctos (organizacao_id, negocio_id, codigo, latitude, longitude, quantidade_portas, splitter)
  values (v.org, v.neg, 'cto-901', -23.55, -46.63, 8, '1x8') returning id into v_cto;
  assert (select count(*) from public.cto_portas where cto_id = v_cto) = 8, 'T1 8 portas geradas';
  assert (select codigo from public.ctos where id = v_cto) = 'CTO-901', 'T1 código em maiúsculas';
  update public.ctos set quantidade_portas = 16 where id = v_cto;
  assert (select count(*) from public.cto_portas where cto_id = v_cto) = 16, 'T1 16 portas após aumento';
  update public.ctos set quantidade_portas = 8 where id = v_cto;
  assert (select count(*) from public.cto_portas where cto_id = v_cto) = 8, 'T1 redução com portas livres';
end $$;

-- T2: vincular exige contrato ativo do negócio; escrita direta bloqueada; 1 porta por cliente
do $$ declare v r%rowtype; v_cto uuid; v_porta uuid; pt public.cto_portas; begin
  select * into v from r;
  select id into v_cto from public.ctos where codigo = 'CTO-901';
  select id into v_porta from public.cto_portas where cto_id = v_cto and numero = 1;
  begin
    perform public.vincular_porta_cto(v_porta, v.p3, v.ct3);
    raise exception 'T2 contrato encerrado deveria falhar';
  exception when check_violation then null; end;
  pt := public.vincular_porta_cto(v_porta, v.p1, v.ct1);
  assert pt.status = 'ocupada' and pt.data_ocupacao = current_date, 'T2 porta ocupada';
  begin
    perform public.vincular_porta_cto((select id from public.cto_portas where cto_id = v_cto and numero = 2), v.p1, v.ct1);
    raise exception 'T2 segunda porta do mesmo cliente deveria falhar';
  exception when unique_violation then null; end;
  perform set_config('erp.motor', '', true);
  begin
    update public.cto_portas set status = 'livre', pessoa_id = null where id = v_porta;
    raise exception 'T2 escrita direta deveria falhar';
  exception when insufficient_privilege then null; end;
  assert (select count(*) from public.cto_historico where porta_id = v_porta and evento = 'ocupacao') = 1, 'T2 histórico de ocupação';
end $$;

-- T3: defeito bloqueia ocupação; reserva com cliente vira ocupada ao instalar
do $$ declare v r%rowtype; v_cto uuid; v_porta uuid; pt public.cto_portas; begin
  select * into v from r;
  select id into v_cto from public.ctos where codigo = 'CTO-901';
  select id into v_porta from public.cto_portas where cto_id = v_cto and numero = 3;
  perform public.defeito_porta_cto(v_porta, true, 'conector quebrado');
  begin
    perform public.vincular_porta_cto(v_porta, v.p2, v.ct2);
    raise exception 'T3 porta com defeito deveria falhar';
  exception when check_violation then null; end;
  perform public.defeito_porta_cto(v_porta, false, 'reparado');
  pt := public.vincular_porta_cto(v_porta, v.p2, v.ct2, true);
  assert pt.status = 'reservada' and pt.data_ocupacao is null, 'T3 reservada com cliente';
  pt := public.vincular_porta_cto(v_porta, v.p2, v.ct2, false);
  assert pt.status = 'ocupada' and pt.data_ocupacao = current_date, 'T3 reserva efetivada';
end $$;

-- T4: liberar deixa drop disponível; trocar move o cliente e registra os dois lados
do $$ declare v r%rowtype; v_cto uuid; v_p1 uuid; v_p5 uuid; pt public.cto_portas; begin
  select * into v from r;
  select id into v_cto from public.ctos where codigo = 'CTO-901';
  select id into v_p1 from public.cto_portas where cto_id = v_cto and numero = 1;
  select id into v_p5 from public.cto_portas where cto_id = v_cto and numero = 5;
  pt := public.trocar_porta_cto(v_p1, v_p5);
  assert pt.pessoa_id = v.p1 and pt.status = 'ocupada', 'T4 cliente na porta nova';
  assert (select drop_disponivel from public.cto_portas where id = v_p1), 'T4 porta antiga com drop disponível';
  assert (select count(*) from public.cto_historico where evento = 'troca' and porta_id in (v_p1, v_p5)) = 2, 'T4 troca nos dois lados';
  pt := public.liberar_porta_cto(v_p5, 'cancelou');
  assert pt.status = 'livre' and pt.drop_disponivel and pt.pessoa_id is null, 'T4 liberada com drop';
  assert (select ocupadas from public.vw_ctos_ocupacao where id = v_cto) = 1, 'T4 ocupação da view (só T3)';
  assert (select drops_disponiveis from public.vw_ctos_ocupacao where id = v_cto) = 2, 'T4 drops disponíveis na view';
end $$;

-- T5 (0048): POP, fio POP→CTO e local do cliente na porta
do $$ declare v r%rowtype; v_pop uuid; v_cto uuid; v_porta uuid; pt public.cto_portas; begin
  select * into v from r;
  insert into public.ctos (organizacao_id, negocio_id, codigo, latitude, longitude, quantidade_portas, tipo)
  values (v.org, v.neg, 'POP-01', -23.50, -46.60, 1, 'pop') returning id into v_pop;
  select id into v_cto from public.ctos where codigo = 'CTO-901';
  update public.ctos set pop_id = v_pop where id = v_cto;
  assert (select pop_id from public.ctos where id = v_cto) = v_pop, 'T5 fio POP→CTO';
  begin
    update public.ctos set pop_id = v_cto where id = v_cto;
    raise exception 'T5 apontar para si mesma deveria falhar';
  exception when check_violation then null; end;
  select p.id into v_porta from public.cto_portas p where p.cto_id = v_cto and p.status = 'ocupada' limit 1;
  pt := public.local_cliente_porta(v_porta, -23.51, -46.61);
  assert pt.cliente_latitude = -23.51, 'T5 local do cliente gravado';
  begin
    perform public.local_cliente_porta((select p.id from public.cto_portas p where p.cto_id = v_cto and p.status = 'livre' limit 1), -23.5, -46.6);
    raise exception 'T5 local em porta livre deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T6 (0049): rotas com vértices — POP→CTO e CTO→cliente (último ponto = cliente)
do $$ declare v r%rowtype; v_cto uuid; v_porta uuid; c public.ctos; pt public.cto_portas; begin
  select * into v from r;
  select id into v_cto from public.ctos where codigo = 'CTO-901';
  c := public.rota_pop_cto(v_cto, '[[-23.505,-46.605],[-23.51,-46.61]]'::jsonb);
  assert jsonb_array_length(c.rota_pop) = 2, 'T6 rota POP→CTO com 2 vértices';
  begin
    perform public.rota_pop_cto(v_cto, '[[999,0]]'::jsonb);
    raise exception 'T6 rota inválida deveria falhar';
  exception when check_violation then null; end;
  select p.id into v_porta from public.cto_portas p where p.cto_id = v_cto and p.status = 'ocupada' limit 1;
  pt := public.rota_cliente_porta(v_porta, '[[-23.551,-46.631],[-23.552,-46.632],[-23.553,-46.633]]'::jsonb);
  assert pt.cliente_latitude = -23.553 and jsonb_array_length(pt.rota_cliente) = 3, 'T6 rota do cliente com último ponto';
end $$;

-- T7 (0051): lacre numerado único por organização
do $$ declare v r%rowtype; v_cto uuid; v_p1 uuid; v_p2 uuid; pt public.cto_portas; begin
  select * into v from r;
  select id into v_cto from public.ctos where codigo = 'CTO-901';
  select id into v_p1 from public.cto_portas where cto_id = v_cto and numero = 1;
  select id into v_p2 from public.cto_portas where cto_id = v_cto and numero = 2;
  pt := public.lacre_porta_cto(v_p1, '0678901');
  assert pt.lacre = '0678901', 'T7 lacre gravado';
  begin
    perform public.lacre_porta_cto(v_p2, '0678901');
    raise exception 'T7 lacre duplicado deveria falhar';
  exception when unique_violation then null; end;
  pt := public.lacre_porta_cto(v_p1, '');
  assert pt.lacre is null, 'T7 lacre removido';
end $$;

rollback;
\echo OK
