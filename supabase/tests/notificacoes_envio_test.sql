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
rollback;
\echo OK
