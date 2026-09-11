-- Testes da migration 0073 (régua de cobrança configurável). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_p uuid; v_plano uuid; v_conta uuid; begin
  select org into v_org from ids;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Caixa Régua', 'dinheiro') returning id into v_conta;
  insert into public.negocios (organizacao_id, nome, slug, ativo, conta_padrao_id, categoria_receita_id)
  values (v_org, 'REGUA T', 'regua-t', true, v_conta, (select id from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1)) returning id into v_neg;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Régua', '92988886666') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Régua', 100, 'mensal') returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p, v_plano, 100, 'mensal', date '2026-09-01', 10, v_conta);
  perform public.gerar_faturamento_agora(date '2026-09-30');
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='regua-t') neg,
  (select id from public.pessoas where nome='Cliente Régua') pessoa;

-- T1: padrão enxuto (2 antes · no dia · 3 depois); normalização ordena e tira repetição
do $$ declare v r%rowtype; c public.notificacoes_config; begin
  select * into v from r;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo) values (v.org, v.neg, '+5511954490002', true) returning * into c;
  assert c.regua_antes = '{2}'::smallint[] and c.regua_apos = '{3}'::smallint[] and c.dias_antes = 2 and c.dias_apos = 3, 'T1 padrão enxuto';
  update public.notificacoes_config set regua_antes = '{5,2,5}', regua_apos = '{1,3}' where id = c.id returning * into c;
  assert c.regua_antes = '{2,5}'::smallint[] and c.dias_antes = 5 and c.regua_apos = '{1,3}'::smallint[] and c.dias_apos = 3, 'T1 normalizada e derivada';
end $$;

-- T2: validações da régua
do $$ declare v r%rowtype; begin
  select * into v from r;
  begin
    update public.notificacoes_config set regua_antes = '{40}' where negocio_id = v.neg;
    raise exception 'T2 antes > 30 deveria falhar';
  exception when check_violation then null; end;
  begin
    update public.notificacoes_config set regua_apos = '{0}' where negocio_id = v.neg;
    raise exception 'T2 depois < 1 deveria falhar';
  exception when check_violation then null; end;
  begin
    update public.notificacoes_config set regua_antes = '{1,2,3,4,5,6}' where negocio_id = v.neg;
    raise exception 'T2 mais de 5 pontos deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: cada ponto dispara uma vez — régua {2,5} antes / {1,3} depois, venc. 10/09
do $$ declare v r%rowtype; rel jsonb; begin
  select * into v from r;
  rel := public.executar_notificacoes_agora(date '2026-09-05');  -- D-5
  assert (select count(*) from public.notificacoes_log where pessoa_id = v.pessoa and tipo = 'proximo_vencimento' and dias = 5) = 1, 'T3 aviso D-5';
  rel := public.executar_notificacoes_agora(date '2026-09-05');
  assert (select count(*) from public.notificacoes_log where pessoa_id = v.pessoa and tipo = 'proximo_vencimento') = 1, 'T3 idempotente';
  rel := public.executar_notificacoes_agora(date '2026-09-08');  -- D-2
  assert (select count(*) from public.notificacoes_log where pessoa_id = v.pessoa and tipo = 'proximo_vencimento' and dias = 2) = 1, 'T3 aviso D-2';
  rel := public.executar_notificacoes_agora(date '2026-09-10');  -- no dia
  assert (select count(*) from public.notificacoes_log where pessoa_id = v.pessoa and tipo = 'vencimento' and dias = 0) = 1, 'T3 no dia';
  rel := public.executar_notificacoes_agora(date '2026-09-11');  -- D+1
  rel := public.executar_notificacoes_agora(date '2026-09-13');  -- D+3
  assert (select count(*) from public.notificacoes_log where pessoa_id = v.pessoa and tipo = 'bloqueio') = 2
     and (select count(*) from public.notificacoes_log where pessoa_id = v.pessoa and tipo = 'bloqueio' and dias = 1) = 1
     and (select count(*) from public.notificacoes_log where pessoa_id = v.pessoa and tipo = 'bloqueio' and dias = 3) = 1, 'T3 avisos D+1 e D+3';
  -- dia fora da régua não gera nada
  rel := public.executar_notificacoes_agora(date '2026-09-07');
  assert (select count(*) from public.notificacoes_log where pessoa_id = v.pessoa) = 5, 'T3 fora da régua não gera';
end $$;

-- T4: régua vazia antes = nenhum aviso antes; dias_apos derivado continua para o bloqueio assistido
do $$ declare v r%rowtype; c public.notificacoes_config; rel jsonb; begin
  select * into v from r;
  -- com {4} o dia 06/09 (D-4) geraria aviso; com a régua vazia, nada
  update public.notificacoes_config set regua_antes = '{}' where negocio_id = v.neg returning * into c;
  assert c.dias_antes = 0 and c.dias_apos = 3, 'T4 derivados';
  rel := public.executar_notificacoes_agora(date '2026-09-06');
  assert (select count(*) from public.notificacoes_log where pessoa_id = v.pessoa) = 5, 'T4 sem aviso antes';
end $$;

rollback;
\echo OK
