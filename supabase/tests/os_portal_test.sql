-- Testes da migration 0057 (visita técnica pelo portal + avisos WhatsApp da OS). Saída "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values ('55555555-5555-5555-5555-555555555555', 'cliente-os@teste.dev', '{"portal":"true"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

-- setup admin: negócio com notificações ativas (simulado), cliente com telefone/avisos, contrato, técnico
do $$ declare v_org uuid; v_neg uuid; v_p uuid; v_pt uuid; v_plano uuid; v_conta uuid; v_tec uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'PORTAL OS', 'portal-os', true) returning id into v_neg;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo) values (v_org, v_neg, '+5592999990000', true);
  insert into public.pessoas (organizacao_id, nome, telefone, endereco, receber_avisos) values (v_org, 'Cliente Portal OS', '92988885555', 'Rua B, 20', true) returning id into v_p;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Téc Portal') returning id into v_pt;
  insert into public.tecnicos (organizacao_id, negocio_id, pessoa_id, nome) values (v_org, v_neg, v_pt, 'Téc Portal') returning id into v_tec;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Portal OS', 120, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Portal OS', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p, v_plano, 120, 'mensal', current_date, 10, v_conta);
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='portal-os') neg,
  (select id from public.pessoas where nome='Cliente Portal OS') pessoa,
  (select id from public.tecnicos where nome='Téc Portal') tec;

-- vincula o login do portal (como faz o login por CPF, via service_role)
grant select on r to service_role;
set local role service_role;
do $$ begin perform public.portal_vincular_servico((select pessoa from r), '55555555-5555-5555-5555-555555555555'); end $$;
set local role authenticated;

-- T1: cliente abre visita pelo portal — vira OS com contrato, técnico automático e urgência para "sem internet"
set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
do $$ declare v r%rowtype; res record; vis record; n int; begin
  select * into v from r;
  select * into res from public.portal_abrir_visita(v.neg, 'sem_internet', 'luz vermelha no modem');
  assert res.numero like 'OS%' and res.tecnico = 'Téc Portal', 'T1 visita virou OS: ' || res.numero;
  select count(*) into n from public.ordens_servico;
  assert n = 0, 'T1 tabela de OS continua invisível ao portal';
  select * into vis from public.portal_minhas_visitas();
  assert vis.numero = res.numero and vis.tipo = 'reparo' and vis.aberto_via = 'portal' and vis.tecnico = 'Téc Portal', 'T1 dados da visita';
  -- só uma visita em andamento por vez
  begin
    perform public.portal_abrir_visita(v.neg, 'lentidao', 'de novo');
    raise exception 'T1 segunda visita em andamento deveria falhar';
  exception when check_violation then null; end;
  -- acompanhamento
  select count(*) into n from public.portal_minhas_visitas();
  assert n = 1, 'T1 minhas visitas';
end $$;

-- T2: técnico/admin agenda → aviso WhatsApp entra na fila; remarcação com aval do cliente reenvia
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; v_os uuid; n int; begin
  select * into v from r;
  select id into v_os from public.ordens_servico where pessoa_id = v.pessoa and aberto_via = 'portal';
  assert (select prioridade::text from public.ordens_servico where id = v_os) = 'urgente'
     and (select contrato_id from public.ordens_servico where id = v_os) is not null, 'T2 urgência e contrato da visita';
  perform public.agendar_os(v_os, current_date, '14:00');
  select count(*) into n from public.notificacoes_log where os_id = v_os and tipo::text = 'os_agendada';
  assert n = 1, 'T2 aviso de agendamento na fila: ' || n;
  assert (select mensagem from public.notificacoes_log where os_id = v_os limit 1) like '%14:00%', 'T2 mensagem com a hora';
  assert (select status::text from public.notificacoes_log where os_id = v_os limit 1) = 'simulado', 'T2 provedor simulado registra na hora';
  perform public.solicitar_remarcacao_os(v_os, current_date + 1, '09:00', 'chuva forte');
end $$;

-- cliente aprova a remarcação pelo portal → data muda e novo aviso sai
set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
do $$ declare v r%rowtype; v_os uuid; n int; begin
  select * into v from r;
  select id into v_os from (select * from public.portal_minhas_visitas()) x;
  perform public.portal_responder_remarcacao(v_os, true);
  assert (select data_agendada from public.portal_minhas_visitas() limit 1) = current_date + 1, 'T2 remarcação aprovada pelo cliente';
  select count(*) into n from public.notificacoes_log;
  assert n = 0, 'T2 fila de avisos invisível ao portal';
  -- cliente não avalia chamado aberto
  begin
    perform public.portal_avaliar_visita(v_os, true, 5);
    raise exception 'T2 avaliar chamado aberto deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: encerramento avisa uma vez só; cliente avalia "não resolvido" e reabre (-A urgente)
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; v_os uuid; n int; begin
  select * into v from r;
  select id into v_os from public.ordens_servico where pessoa_id = v.pessoa and aberto_via = 'portal';
  select count(*) into n from public.notificacoes_log where os_id = v_os and tipo::text = 'os_agendada';
  assert n = 2, 'T3 novo aviso após remarcação aprovada: ' || n;
  perform public.iniciar_os(v_os);
  perform public.encerrar_os(v_os, '[]'::jsonb, 'roteador_cliente', null, 'reiniciado');
  select count(*) into n from public.notificacoes_log where os_id = v_os and tipo::text = 'os_encerrada';
  assert n = 1, 'T3 aviso de encerramento';
end $$;
set local request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
do $$ declare v r%rowtype; v_os uuid; vis record; n int; begin
  select * into v from r;
  select id into v_os from (select * from public.portal_minhas_visitas() where status = 'encerrado') x;
  perform public.portal_avaliar_visita(v_os, false, null, true);
  select * into vis from public.portal_minhas_visitas() where status <> 'encerrado';
  assert vis.numero like '%-A' and vis.aberto_via = 'portal' and vis.tecnico = 'Téc Portal', 'T3 reabertura pelo cliente: ' || vis.numero;
  begin
    perform public.portal_avaliar_visita(v_os, true, 5);
    raise exception 'T3 avaliar duas vezes deveria falhar';
  exception when check_violation then null; end;
  select count(*) into n from public.portal_minhas_visitas();
  assert n = 2, 'T3 acompanhamento mostra as duas';
end $$;

-- T4: reabertura urgente no banco; outro usuário do portal não age nas visitas deste cliente
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert exists (select 1 from public.ordens_servico where pessoa_id = v.pessoa and numero like '%-A' and prioridade = 'urgente' and status = 'aberto'), 'T4 reabertura urgente registrada';
  create temp table alvo as select id from public.ordens_servico where pessoa_id = v.pessoa and status = 'encerrado' limit 1;
end $$;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
do $$ declare v_os uuid; begin
  select id into v_os from alvo;
  assert v_os is not null, 'T4 alvo capturado';
  begin
    perform public.portal_avaliar_visita(v_os, true, 5);
    raise exception 'T4 avaliar visita alheia deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

rollback;
\echo OK
