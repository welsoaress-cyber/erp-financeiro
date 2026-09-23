-- Testes da migration 0097 (bloqueio/desbloqueio automático, opt-in). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg_auto uuid; v_neg_manual uuid; v_p1 uuid; v_p2 uuid; v_p3 uuid; v_plano uuid;
  v_conta uuid; v_ct1 uuid; v_ct2 uuid; v_ct3 uuid; v_cat uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'BLQ AUTO', 'blq-auto', true) returning id into v_neg_auto;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'BLQ MANUAL', 'blq-manual', true) returning id into v_neg_manual;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, dias_apos, bloqueio_automatico) values (v_org, v_neg_auto, '+5592999990003', true, 5, true);
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, dias_apos, bloqueio_automatico) values (v_org, v_neg_manual, '+5592999990004', true, 5, false);

  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Auto Vencido', '92988886001') returning id into v_p1;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Auto Em Dia', '92988886002') returning id into v_p2;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Manual Vencido', '92988886003') returning id into v_p3;

  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg_auto, 'Plano Auto', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Auto', 'dinheiro', v_neg_auto) returning id into v_conta;

  -- contrato ativo, vencido há mais que a régua (5 dias) → deve ser suspenso sozinho
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg_auto, v_p1, v_plano, 100, 'mensal', current_date - 90, 10, v_conta, 'ativo') returning id into v_ct1;
  -- contrato SUSPENSO sem nada vencido → deve ser reativado sozinho
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg_auto, v_p2, v_plano, 100, 'mensal', current_date - 90, 10, v_conta, 'suspenso') returning id into v_ct2;
  -- mesmo cenário do ct1, mas no negócio SEM bloqueio_automatico → não pode mexer sozinho
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg_manual, 'Plano Manual', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Manual', 'dinheiro', v_neg_manual) returning id into v_conta;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg_manual, v_p3, v_plano, 100, 'mensal', current_date - 90, 10, v_conta, 'ativo') returning id into v_ct3;

  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  perform public.criar_lancamento('receita', 'Vencida auto', 100, current_date - 30, current_date - 30, null,
    (select conta_id from public.contratos where id = v_ct1), null, v_cat, null, v_neg_auto, v_p1, v_ct1);
  perform public.criar_lancamento('receita', 'Vencida manual', 100, current_date - 30, current_date - 30, null,
    (select conta_id from public.contratos where id = v_ct3), null, v_cat, null, v_neg_manual, v_p3, v_ct3);
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='blq-auto') neg_auto,
  (select id from public.negocios where slug='blq-manual') neg_manual,
  (select id from public.contratos where pessoa_id = (select id from public.pessoas where nome='Cliente Auto Vencido')) ct1,
  (select id from public.contratos where pessoa_id = (select id from public.pessoas where nome='Cliente Auto Em Dia')) ct2,
  (select id from public.contratos where pessoa_id = (select id from public.pessoas where nome='Cliente Manual Vencido')) ct3;
grant select on r to service_role;

set local role service_role; -- é assim que o pg_cron chama (postgres/superuser na prática, service_role aqui simula "sem sessão de usuário")

-- T1: roda o robô — bloqueia o vencido, desbloqueia o em dia, no negócio com bloqueio_automatico ligado
do $$ declare v r%rowtype; res jsonb; begin
  select * into v from r;
  res := public.executar_bloqueios_automaticos();
  assert (res->>'executados')::int >= 2, 'T1 executou pelo menos os dois casos do negócio automático: ' || res;
  assert (select status from public.contratos where id = v.ct1) = 'suspenso', 'T1 contrato vencido virou suspenso sozinho';
  assert (select status from public.contratos where id = v.ct2) = 'ativo', 'T1 contrato em dia foi reativado sozinho';
end $$;

-- T2: o bloqueio ficou marcado como automático, sem usuário, e status executado
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert exists (
    select 1 from public.bloqueios where contrato_id = v.ct1 and tipo = 'bloqueio' and status = 'executado' and automatico and usuario_id is null
  ), 'T2 bloqueio marcado automático, sem usuário';
  assert exists (
    select 1 from public.bloqueios where contrato_id = v.ct2 and tipo = 'desbloqueio' and status = 'executado' and automatico
  ), 'T2 desbloqueio marcado automático';
end $$;

-- T3: negócio SEM bloqueio_automatico não é tocado pelo robô
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select status from public.contratos where id = v.ct3) = 'ativo', 'T3 negócio manual não é mexido pelo robô';
  assert not exists (select 1 from public.bloqueios where contrato_id = v.ct3), 'T3 nem sugestão foi gerada pro negócio manual';
end $$;

-- T4: relatório mostra "Automático" nos dois casos do negócio automático
set local role authenticated;
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select count(*) from public.vw_rel_bloqueios where negocio_id = v.neg_auto and automatico = 'Automático') = 2, 'T4 relatório com os dois automáticos';
end $$;

-- T5: rodar de novo não duplica nem refaz o que já foi executado
do $$ declare v r%rowtype; antes int; depois int; begin
  select * into v from r;
  select count(*) into antes from public.bloqueios where negocio_id = v.neg_auto;
  set local role service_role;
  perform public.executar_bloqueios_automaticos();
  set local role authenticated;
  select count(*) into depois from public.bloqueios where negocio_id = v.neg_auto;
  assert antes = depois, 'T5 rodar de novo não duplica: ' || antes || ' -> ' || depois;
end $$;

-- T6: executar_bloqueios_agora (botão manual) faz o mesmo que o robô, na hora, para
-- quem já está com bloqueio_automatico ligado — sem esperar virar o dia.
do $$ declare v r%rowtype; v_p4 uuid; v_plano uuid; v_conta uuid; v_ct4 uuid; v_cat uuid; res jsonb; begin
  select * into v from r;
  select plano_id, conta_id into v_plano, v_conta from public.contratos where id = v.ct1;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v.org, 'Cliente Auto Vencido 2', '92988886005') returning id into v_p4;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v.org, v.neg_auto, v_p4, v_plano, 100, 'mensal', current_date - 90, 10, v_conta, 'ativo') returning id into v_ct4;
  select id into v_cat from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1;
  perform public.criar_lancamento('receita', 'Vencida auto 2', 100, current_date - 30, current_date - 30, null, v_conta, null, v_cat, null, v.neg_auto, v_p4, v_ct4);
  res := public.executar_bloqueios_agora(v.neg_auto);
  assert (res->>'executados')::int >= 1, 'T6 botão manual executou o novo vencido: ' || res;
  assert (select status from public.contratos where id = v_ct4) = 'suspenso', 'T6 contrato suspenso na hora, via botão';
end $$;

-- T7: negócio SEM bloqueio_automatico não pode usar o botão (fluxo continua assistido, um a um)
do $$ declare v r%rowtype; falhou boolean := false; begin
  select * into v from r;
  begin
    perform public.executar_bloqueios_agora(v.neg_manual);
  exception when check_violation then falhou := true;
  end;
  assert falhou, 'T7 botão recusado para negócio sem bloqueio_automatico ligado';
end $$;

rollback;
\echo OK
