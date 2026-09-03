-- Testes da migration 0016 (notificações WhatsApp, modo simulado). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco', 'corrente' from ids;
insert into public.negocios (organizacao_id, nome, slug, conta_padrao_id, categoria_receita_id)
  select org, 'SERVNET', 'servnet', (select id from public.contas where nome='Banco'), (select id from public.categorias where nome='Salário') from ids;
insert into public.pessoas (organizacao_id, nome, documento, telefone) select org, 'João da Silva', '52998224725', '11988887777' from ids;
insert into public.pessoas (organizacao_id, nome) select org, 'Sem Fone' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) select org, (select id from public.negocios where slug='servnet'), 'Fibra 500', 99.90 from ids;
create temp table r as select (select org from ids) org, (select id from public.negocios where slug='servnet') servnet,
  (select id from public.pessoas where nome='João da Silva') joao, (select id from public.pessoas where nome='Sem Fone') semfone,
  (select id from public.planos where nome='Fibra 500') fibra;
-- contratos com vencimento dia 10, faturar desde este mês → cobrança prevista dia 10
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
  select org, servnet, joao, fibra, 99.90, 'mensal', date '2026-09-01', 10 from r;
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
  select org, servnet, semfone, fibra, 99.90, 'mensal', date '2026-09-01', 10 from r;
select public.gerar_faturamento_agora(date '2026-09-30');

-- T0: helpers
do $$ begin
  assert public.numero_e164('11988887777') = '+5511988887777', 'T0 celular BR';
  assert public.numero_e164('1133334444') = '+551133334444', 'T0 fixo BR';
  assert public.numero_e164('5511988887777') = '+5511988887777', 'T0 já com DDI';
  assert public.renderizar_template('Oi {nome}, {valor} em {vencimento}', '{"nome":"Ana","valor":"R$ 9,90","vencimento":"10/09/2026"}') = 'Oi Ana, R$ 9,90 em 10/09/2026', 'T0 template';
  assert public.moeda_br(1234.5) = 'R$ 1.234,50', 'T0 moeda: ' || public.moeda_br(1234.5);
end $$;

-- T1: configuração — número validado/normalizado; ativar exige número; templates com tamanho mínimo
do $$ declare v r%rowtype; c public.notificacoes_config; begin
  select * into v from r;
  begin
    insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo) values (v.org, v.servnet, null, true);
    raise exception 'T1 ativo sem número deveria falhar';
  exception when check_violation then null; end;
  begin
    insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp) values (v.org, v.servnet, '11954490001');
    raise exception 'T1 número sem + deveria falhar';
  exception when check_violation then null; end;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo) values (v.org, v.servnet, '+55 (11) 95449-0001', true) returning * into c;
  assert c.numero_whatsapp = '+5511954490001' and c.dias_antes = 3 and c.dias_apos = 3 and c.provedor = 'simulado', 'T1 normalizado e padrões';
  begin
    update public.notificacoes_config set template_bloqueio = 'curto' where id = c.id;
    raise exception 'T1 template curto deveria falhar';
  exception when check_violation then null; end;
  begin
    insert into public.notificacoes_log (organizacao_id, negocio_id, pessoa_id, tipo, data_referencia, mensagem) values (v.org, v.servnet, v.joao, 'teste', current_date, 'x');
    raise exception 'T1 log direto deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

-- T2: geração — 3 dias antes, no dia, 3 dias após; idempotente; sem telefone = erro; mensagem renderizada
do $$ declare v r%rowtype; rel jsonb; g public.notificacoes_log; n int; begin
  select * into v from r;
  rel := public.executar_notificacoes_agora(date '2026-09-07');  -- 3 dias antes do dia 10
  assert (rel->>'geradas')::int = 2, 'T2 geradas D-3: ' || rel::text;
  select * into g from public.notificacoes_log where pessoa_id = v.joao and tipo = 'proximo_vencimento';
  assert found and g.numero_destino = '+5511988887777' and g.mensagem like 'Olá João da Silva! Sua fatura do SERVNET (Fibra 500) no valor de R$ 99,90 vence em 10/09/2026%', 'T2 mensagem: ' || g.mensagem;
  assert (select status from public.notificacoes_log where pessoa_id = v.semfone and tipo = 'proximo_vencimento') = 'erro', 'T2 sem telefone = erro';
  rel := public.executar_notificacoes_agora(date '2026-09-07');
  assert (rel->>'geradas')::int = 0, 'T2 idempotente';
  rel := public.executar_notificacoes_agora(date '2026-09-08');
  assert (rel->>'geradas')::int = 0, 'T2 dia sem evento';
  rel := public.executar_notificacoes_agora(date '2026-09-10');
  assert (rel->>'geradas')::int = 2 and (select count(*) from public.notificacoes_log where tipo = 'vencimento') = 2, 'T2 no dia';
  begin
    rel := public.executar_notificacoes_agora(current_date + 60);
    raise exception 'T2 data distante deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: processamento — horário comercial; simulado dentro; pendente fora; pago antes do envio = erro; encerrado não gera
do $$ declare v r%rowtype; rel jsonb; n int; l uuid; c uuid; begin
  select * into v from r;
  -- as pendentes de T2 foram processadas por executar_notificacoes_agora com now(): depende da hora atual. Verifica coerência:
  select count(*) into n from public.notificacoes_log where status = 'pendente';
  if (now() at time zone 'America/Sao_Paulo')::time between time '08:00' and time '17:59:59' then
    assert n = 0, 'T3 dentro do horário: nada pendente';
  else
    assert n = 2, 'T3 fora do horário: 2 pendentes (' || n || ')';
  end if;
  -- força cenários com hora explícita pela função interna (definer; teste roda como authenticated → usa via executar_notificacoes com role)
  reset role;
  perform public.processar_notificacoes(v.org, timestamp with time zone '2026-09-10 12:00:00-03');  -- 12:00 BRT
  assert (select count(*) from public.notificacoes_log where status = 'pendente') = 0, 'T3 processadas às 12:00';
  assert (select count(*) from public.notificacoes_log where status = 'simulado' and data_envio is not null) = 2, 'T3 simuladas com data_envio';
  -- bloqueio D+3: cobrança do João paga antes → erro; Sem Fone continua sem telefone → erro
  select id into l from public.lancamentos where contrato_id = (select id from public.contratos where pessoa_id = v.joao) and status = 'previsto';
  perform public.gerar_notificacoes(v.org, date '2026-09-13');
  assert (select status from public.notificacoes_log where lancamento_id = l and tipo = 'bloqueio') = 'pendente', 'T3 bloqueio gerado pendente';
  set local role authenticated;
  perform public.efetivar_lancamento(l, date '2026-09-12');
  reset role;
  perform public.processar_notificacoes(v.org, timestamp with time zone '2026-09-13 23:00:00-03');  -- 23:00: fora do horário
  assert (select status from public.notificacoes_log where lancamento_id = l and tipo = 'bloqueio') = 'pendente', 'T3 fora do horário fica pendente';
  perform public.processar_notificacoes(v.org, timestamp with time zone '2026-09-14 09:00:00-03');
  assert (select status from public.notificacoes_log where lancamento_id = l and tipo = 'bloqueio') = 'erro', 'T3 paga antes do envio → erro, não avisa';
  -- contrato encerrado: nada gerado
  set local role authenticated;
  select id into c from public.contratos where pessoa_id = v.semfone;
  update public.contratos set status = 'encerrado', data_fim = date '2026-09-11' where id = c;
  perform public.cancelar_lancamento((select id from public.lancamentos where contrato_id = c and status = 'previsto'), 'encerrado');
  reset role;
  assert public.gerar_notificacoes(v.org, date '2026-09-13') = 0, 'T3 encerrado não gera bloqueio';
  -- config desativada: nada gerado no mês seguinte
  set local role authenticated;
  update public.notificacoes_config set ativo = false where negocio_id = v.servnet;
  perform public.gerar_faturamento_agora(date '2026-10-31');
  reset role;
  assert public.gerar_notificacoes(v.org, date '2026-10-07') = 0, 'T3 desativado não gera';
  set local role authenticated;
end $$;

-- T4: teste manual; imutabilidade do log; anon
do $$ declare v r%rowtype; g public.notificacoes_log; begin
  select * into v from r;
  update public.notificacoes_config set ativo = true where negocio_id = v.servnet;
  g := public.enviar_notificacao_teste(v.servnet, v.joao, 'bloqueio');
  assert g.tipo = 'teste' and g.status = 'simulado' and g.mensagem like '[TESTE] Olá João da Silva.%' and g.numero_destino = '+5511988887777', 'T4 teste: ' || g.mensagem;
  begin
    perform public.enviar_notificacao_teste(v.servnet, v.semfone);
    raise exception 'T4 sem telefone deveria falhar';
  exception when check_violation then null; end;
  begin
    update public.notificacoes_log set mensagem = 'x' where id = g.id;
    raise exception 'T4 update direto deveria falhar';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.notificacoes_log where id = g.id;
    raise exception 'T4 delete deveria falhar';
  exception when insufficient_privilege then null; end;
  assert (select count(*) from public.vw_notificacoes where pessoa = 'João da Silva') >= 3, 'T4 view';
end $$;
set local role anon;
do $$ begin
  begin
    perform public.executar_notificacoes_agora();
    raise exception 'T4 anon deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
\echo OK
