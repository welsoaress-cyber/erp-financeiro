-- Testes da migration 0061 (CEO e encadeamento). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_pop uuid; v_ceo uuid; v_ceo2 uuid; v_cto uuid; v_p uuid; v_plano uuid; v_conta uuid; v_ct uuid; v_porta uuid; n int; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'CEO T', 'ceo-t', true) returning id into v_neg;
  insert into public.ctos (organizacao_id, negocio_id, codigo, latitude, longitude, quantidade_portas, tipo, olt_marca, olt_ip, olt_portas_pon)
  values (v_org, v_neg, 'POP-CEO', -3.0, -60.0, 1, 'pop', 'Huawei', '10.0.0.2', 16) returning id into v_pop;
  -- CEO alimentada pelo POP; segunda CEO em cascata; CTO na ponta
  insert into public.ctos (organizacao_id, negocio_id, codigo, latitude, longitude, quantidade_portas, tipo, pop_id, splitter)
  values (v_org, v_neg, 'CEO-01', -3.01, -60.01, 1, 'ceo', v_pop, '1x8') returning id into v_ceo;
  insert into public.ctos (organizacao_id, negocio_id, codigo, latitude, longitude, quantidade_portas, tipo, pop_id)
  values (v_org, v_neg, 'CEO-02', -3.02, -60.02, 1, 'ceo', v_ceo) returning id into v_ceo2;
  insert into public.ctos (organizacao_id, negocio_id, codigo, latitude, longitude, quantidade_portas, tipo, pop_id)
  values (v_org, v_neg, 'CTO-CEO', -3.03, -60.03, 8, 'cto', v_ceo2) returning id into v_cto;
  -- ciclo proibido: CEO-01 alimentada pela CEO-02 (que desce dela)
  begin
    update public.ctos set pop_id = v_ceo2 where id = v_ceo;
    raise exception 'T1 ciclo deveria falhar';
  exception when check_violation then null; end;
  -- CTO não alimenta ninguém como pai? (CTO só pode apontar para pop/ceo)
  begin
    update public.ctos set pop_id = v_cto where id = v_ceo2;
    raise exception 'T1 pai CTO deveria falhar';
  exception when check_violation then null; end;
  -- cliente na ponta para contar impacto
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Cliente CEO') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano CEO', 90, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa CEO', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p, v_plano, 90, 'mensal', current_date, 10, v_conta) returning id into v_ct;
  select id into v_porta from public.cto_portas where cto_id = v_cto and numero = 1;
  perform public.vincular_porta_cto(v_porta, v_p, v_ct);
  -- impacto: abaixo do POP = 3 pontos, 1 cliente; abaixo da CEO-02 = 1 ponto
  select count(*), sum(clientes)::int into n from public.ftth_abaixo_de(v_pop);
  assert n = 3, 'T2 pontos abaixo do POP: ' || n;
  assert (select sum(clientes) from public.ftth_abaixo_de(v_pop)) = 1, 'T2 clientes afetados';
  assert (select count(*) from public.ftth_abaixo_de(v_ceo2)) = 1, 'T2 abaixo da CEO-02';
  assert (select nivel from public.ftth_abaixo_de(v_pop) where codigo = 'CTO-CEO') = 3, 'T2 nível da CTO';
end $$;

rollback;
\echo OK
