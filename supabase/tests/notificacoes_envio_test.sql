-- Testes da migration 0018 (provedor evolution, opt-out, fila para a Edge Function). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco', 'corrente' from ids;
insert into public.negocios (organizacao_id, nome, slug, conta_padrao_id, categoria_receita_id)
  select org, 'SERVNET', 'servnet', (select id from public.contas where nome='Banco'), (select id from public.categorias where nome='Salário') from ids;
insert into public.pessoas (organizacao_id, nome, documento, telefone) select org, 'João da Silva', '52998224725', '11988887777' from ids;
insert into public.pessoas (organizacao_id, nome, telefone, receber_avisos) select org, 'Optou Não', '11977776666', false from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) select org, (select id from public.negocios where slug='servnet'), 'Fibra 500', 99.90 from ids;
create temp table r as select (select org from ids) org, (select id from public.negocios where slug='servnet') servnet,
  (select id from public.pessoas where nome='João da Silva') joao, (select id from public.pessoas where nome='Optou Não') optou, (select id from public.planos where nome='Fibra 500') fibra;
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento) select org, servnet, joao, fibra, 99.90, 'mensal', date '2026-09-01', 10 from r;
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento) select org, servnet, optou, fibra, 99.90, 'mensal', date '2026-09-01', 10 from r;
select public.gerar_faturamento_agora(date '2026-09-30');
grant select on r to service_role;

-- T1: provedor evolution exige instância; opt-out não gera; pendente fica pendente (não simula)
do $$ declare v r%rowtype; rel jsonb; begin
  select * into v from r;
  begin
    insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, provedor) values (v.org, v.servnet, '+5511954490001', true, 'evolution');
    raise exception 'T1 evolution sem instância deveria falhar';
  exception when check_violation then null; end;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, provedor, instancia) values (v.org, v.servnet, '+5511954490001', true, 'evolution', ' SERVNET ');
  assert (select instancia from public.notificacoes_config where negocio_id = v.servnet) = 'servnet', 'T1 instância normalizada';
  rel := public.executar_notificacoes_agora(date '2026-09-10');
  assert (rel->>'geradas')::int = 1, 'T1 opt-out não gera: ' || rel::text;
  assert (select status from public.notificacoes_log where pessoa_id = v.joao) = 'pendente', 'T1 evolution fica pendente';
  assert (select count(*) from public.notificacoes_log where pessoa_id = v.optou) = 0, 'T1 sem aviso para quem optou não receber';
end $$;

-- T2: fila para a Edge Function (service_role) — horário comercial, instância, resultado enviado/erro com tentativas
reset role;
set local role service_role;
do $$ declare v r%rowtype; f record; n int; g public.notificacoes_log; begin
  select * into v from r;
  select count(*) into n from public.notificacoes_para_envio(50);
  if (now() at time zone 'America/Sao_Paulo')::time between time '08:00' and time '17:59:59' then
    assert n = 1, 'T2 fila dentro do horário: 1 (' || n || ')';
    select * into f from public.notificacoes_para_envio(50);
    assert f.instancia = 'servnet' and f.numero_destino = '+5511988887777' and f.tipo = 'vencimento', 'T2 dados da fila';
  else
    assert n = 0, 'T2 fora do horário: fila vazia';
    select id into f from public.notificacoes_log where pessoa_id = v.joao;
  end if;
  select * into g from public.notificacoes_log where pessoa_id = v.joao;
  perform public.registrar_resultado_notificacao(g.id, false, 'Instância desconectada', null, false);
  select * into g from public.notificacoes_log where id = g.id;
  assert g.status = 'pendente' and g.tentativas = 0 and g.erro like 'Instância%', 'T2 motivo sem consumir tentativa';
  perform public.registrar_resultado_notificacao(g.id, false, 'HTTP 500: instabilidade', '{"e":1}'::jsonb);
  select * into g from public.notificacoes_log where id = g.id;
  assert g.status = 'pendente' and g.tentativas = 1 and g.erro like 'HTTP 500%', 'T2 falha mantém pendente e conta tentativa';
  perform public.registrar_resultado_notificacao(g.id, true, null, '{"key":{"id":"ABC"}}'::jsonb);
  select * into g from public.notificacoes_log where id = g.id;
  assert g.status = 'enviado' and g.data_envio is not null and g.resposta_provedor->'key'->>'id' = 'ABC' and g.tentativas = 2, 'T2 sucesso marca enviado';
  perform public.registrar_resultado_notificacao(g.id, false, 'x');
  assert (select status from public.notificacoes_log where id = g.id) = 'enviado', 'T2 enviado não regride';
end $$;

-- T3: 5 falhas viram erro definitivo; anon/authenticated não acessam a fila
do $$ declare v r%rowtype; g public.notificacoes_log; i int; begin
  select * into v from r;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  g := public.enviar_notificacao_teste(v.servnet, v.joao);
  assert g.status = 'pendente' and g.data_envio is null, 'T3 teste no provedor evolution fica pendente para envio real';
  begin
    perform public.notificacoes_para_envio(10);
    raise exception 'T3 authenticated não deveria ler a fila';
  exception when insufficient_privilege then null; end;
  reset role; set local role service_role;
  for i in 1..5 loop perform public.registrar_resultado_notificacao(g.id, false, 'falha ' || i); end loop;
  select * into g from public.notificacoes_log where id = g.id;
  assert g.status = 'erro' and g.tentativas = 5 and g.erro = 'falha 5', 'T3 erro definitivo após 5 tentativas';
end $$;
-- T4 (0135): envio relê valor/vencimento/telefone atuais na hora de mandar —
-- nunca usa o que ficou gravado na geração do aviso.
do $$ declare v r%rowtype; v_p uuid; v_ct uuid; v_lanc uuid; rel jsonb; f record; begin
  select * into v from r;
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  update public.notificacoes_config set hora_inicio = '00:00', hora_fim = '23:59' where negocio_id = v.servnet;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v.org, 'Cliente Atualiza', '11955550000') returning id into v_p;
  -- contrato nasce já faturado (gatilho de criação): data_inicio no mês do vencimento buscado, sem precisar criar o lançamento à mão
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v.servnet, v_p, v.fibra, 99.90, 'mensal', date '2026-10-01', 15) returning id into v_ct;
  select id into v_lanc from public.lancamentos where contrato_id = v_ct and tipo = 'receita' and status = 'previsto' limit 1;
  assert (select data_vencimento from public.lancamentos where id = v_lanc) = date '2026-10-15', 'T4 lançamento nasceu com o vencimento esperado';
  rel := public.executar_notificacoes_agora(date '2026-10-15');  -- gera o aviso "no dia", com valor/telefone de agora
  assert (select count(*) from public.notificacoes_log where lancamento_id = v_lanc and tipo = 'vencimento') = 1, 'T4 aviso gerado';

  -- dado muda DEPOIS do aviso já gerado (edição real, não UPDATE direto — lancamentos só muda pelo motor)
  perform public.atualizar_lancamento(v_lanc, 'Fibra', 150.00, date '2026-10-15', date '2026-10-15', null, null, null, null, null, v.servnet, v_p, v_ct);
  update public.pessoas set telefone = '11966660000' where id = v_p;

  reset role; set local role service_role;
  select * into f from public.notificacoes_para_envio(50) where tipo = 'vencimento' and numero_destino like '%66660000';
  assert f.numero_destino = '+5511966660000', 'T4 telefone relido na hora de enviar, não o gravado';
  assert f.mensagem like '%150,00%', 'T4 valor relido na hora de enviar: ' || f.mensagem;
  assert f.mensagem not like '%99,90%', 'T4 mensagem não usa o valor velho gravado na geração';

  -- "antes do vencimento" cujo vencimento (atualizado) já passou vira erro, não sai com data errada
  reset role; set local role authenticated; set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  insert into public.pessoas (organizacao_id, nome, telefone) values (v.org, 'Cliente Antecipa', '11955551111') returning id into v_p;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v.servnet, v_p, v.fibra, 99.90, 'mensal', date '2026-10-01', 20) returning id into v_ct;
  select id into v_lanc from public.lancamentos where contrato_id = v_ct and tipo = 'receita' and status = 'previsto' limit 1;
  assert (select data_vencimento from public.lancamentos where id = v_lanc) = date '2026-10-20', 'T4 segundo lançamento nasceu com o vencimento esperado';
  rel := public.executar_notificacoes_agora(date '2026-10-18');  -- D-2, régua padrão
  assert (select count(*) from public.notificacoes_log where lancamento_id = v_lanc and tipo = 'proximo_vencimento') = 1, 'T4 aviso antes gerado';
  perform public.atualizar_lancamento(v_lanc, 'Fibra 2', 99.90, date '2026-10-01', date '2026-10-01', null, null, null, null, null, v.servnet, v_p, v_ct);  -- corrigido pra "já vencida"
  reset role; set local role service_role;
  perform public.notificacoes_para_envio(50);
  assert (select status from public.notificacoes_log where lancamento_id = v_lanc and tipo = 'proximo_vencimento') = 'erro', 'T4 aviso antes vira erro quando o vencimento já passou';
end $$;

rollback;
\echo OK
