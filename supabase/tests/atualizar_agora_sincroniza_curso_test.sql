-- Testes da migration 0119 (botão manual de bloqueio também sincroniza o curso cortesia). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_cat uuid; v_conta uuid; v_negCurso uuid; v_negPago uuid; v_pessoa uuid;
  v_planoCurso uuid; v_planoPago uuid; v_ctCurso uuid; v_ctPago uuid; begin
  select org into v_org from ids;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Caixa Agora Curso', 'dinheiro') returning id into v_conta;
  insert into public.negocios (organizacao_id, nome, slug, ativo, categoria_receita_id, conta_padrao_id) values (v_org, 'Servnet Agora Curso', 'servnet-agora-curso', true, v_cat, v_conta) returning id into v_negCurso;
  insert into public.negocios (organizacao_id, nome, slug, ativo, categoria_receita_id, conta_padrao_id) values (v_org, 'Provedor Agora Pago', 'provedor-agora-pago', true, v_cat, v_conta) returning id into v_negPago;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, dias_apos, bloqueio_apos_dias, bloqueio_automatico) values (v_org, v_negPago, '+5592999990009', true, 5, 5, true);

  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Cliente Agora Curso Dupla') returning id into v_pessoa;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_negCurso, 'Curso Leveduca Agora', 0, 'mensal') returning id into v_planoCurso;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_negPago, 'Internet Agora Pago', 80, 'mensal') returning id into v_planoPago;

  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, cortesia)
  values (v_org, v_negCurso, v_pessoa, v_planoCurso, 0, 'mensal', current_date - 90, 1, true) returning id into v_ctCurso;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_negPago, v_pessoa, v_planoPago, 80, 'mensal', current_date - 90, 10, v_conta, 'ativo') returning id into v_ctPago;

  perform public.criar_lancamento('receita', 'Vencida agora curso', 80, current_date - 30, current_date - 30, null, v_conta, null, v_cat, null, v_negPago, v_pessoa, v_ctPago);

  create temp table ctids as select v_ctCurso as curso, v_ctPago as pago, v_negPago as neg_pago;
end $$;

-- T1: botão "Atualizar bloqueio/desbloqueio agora" suspende o contrato pago vencido
-- e, na mesma chamada, já sincroniza o curso cortesia da mesma pessoa — sem esperar o robô da meia-noite.
do $$ declare v_curso uuid; v_pago uuid; v_neg uuid; res jsonb; begin
  select curso, pago, neg_pago into v_curso, v_pago, v_neg from ctids;
  res := public.executar_bloqueios_agora(v_neg);
  assert (res->>'executados')::int >= 1, 'T1 suspendeu o contrato pago vencido: ' || res;
  assert (res->>'curso_suspensos')::int = 1, 'T1 resultado inclui a sincronização do curso: ' || res;
  assert (select status from public.contratos where id = v_pago) = 'suspenso', 'T1 contrato pago suspenso';
  assert (select status from public.contratos where id = v_curso) = 'suspenso', 'T1 curso cortesia suspenso na mesma chamada, não só na meia-noite';
end $$;

rollback;
\echo OK
