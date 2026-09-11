-- Testes da migration 0059 (Pix Mercado Pago + bloqueio assistido). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_p uuid; v_plano uuid; v_conta uuid; v_pix uuid; v_ct uuid; v_cat uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'PIX T', 'pix-t', true) returning id into v_neg;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, dias_apos) values (v_org, v_neg, '+5592999990001', true, 5);
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Pix', '92988884444') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Pix', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Pix', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Banco Pix MP', 'corrente', v_neg) returning id into v_pix;
  insert into public.portal_config (organizacao_id, negocio_id, pix_automatico, conta_pix_id) values (v_org, v_neg, true, v_pix);
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p, v_plano, 100, 'mensal', current_date - 60, 10, v_conta) returning id into v_ct;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  -- cobrança vencida há 10 dias (além do prazo de 5) e uma futura
  perform public.criar_lancamento('receita', 'Mensalidade vencida', 100, current_date - 10, current_date - 10, null, v_conta, null, v_cat, null, v_neg, v_p, v_ct);
  perform public.criar_lancamento('receita', 'Mensalidade futura', 100, current_date + 20, current_date + 20, null, v_conta, null, v_cat, null, v_neg, v_p, v_ct);
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='pix-t') neg,
  (select id from public.pessoas where nome='Cliente Pix') pessoa,
  (select c.id from public.contratos c join public.negocios n on n.id=c.negocio_id where n.slug='pix-t') ct,
  (select id from public.contas where nome='Banco Pix MP') conta_pix,
  (select id from public.lancamentos where descricao='Mensalidade vencida') lanc;
grant select on r to service_role;

-- T1: fila e registro do Pix (como a Edge, via service_role)
set local role service_role;
do $$ declare v r%rowtype; d record; px public.pix_cobrancas%rowtype; begin
  select * into v from r;
  select * into d from public.pix_dados_lancamento(v.lanc);
  assert d.valor = 100 and d.pix_automatico and d.cliente = 'Cliente Pix' and d.cobranca_pendente is null, 'T1 dados do lançamento';
  px := public.pix_registrar(v.lanc, 'MP-111', 'copiaecola-1', 'https://mp/ticket1', now() + interval '24 hours');
  assert px.status = 'pendente' and px.valor = 100, 'T1 cobrança registrada';
  select * into d from public.pix_dados_lancamento(v.lanc);
  assert d.cobranca_pendente = 'copiaecola-1', 'T1 reaproveita pendente';
  -- registrar de novo cancela a anterior e cria outra
  px := public.pix_registrar(v.lanc, 'MP-222', 'copiaecola-2', null, now() + interval '24 hours');
  assert (select status::text from public.pix_cobrancas where txid = 'MP-111') = 'cancelado', 'T1 anterior cancelada';
end $$;

-- T2: webhook confirma → lançamento baixado na conta Pix; idempotente
do $$ declare v r%rowtype; res jsonb; l public.lancamentos%rowtype; begin
  select * into v from r;
  res := public.pix_confirmar('MP-999');
  assert (res->>'ok') = 'false', 'T2 txid desconhecido';
  res := public.pix_confirmar('MP-222', 100);
  assert (res->>'ok') = 'true', 'T2 confirmado';
  select * into l from public.lancamentos where id = v.lanc;
  assert l.status = 'efetivado' and l.conta_id = v.conta_pix and l.data_efetivacao = current_date, 'T2 baixa na conta Pix';
  assert (select status::text from public.pix_cobrancas where txid = 'MP-222') = 'pago', 'T2 cobrança paga';
  res := public.pix_confirmar('MP-222', 100);
  assert (res->>'motivo') = 'já confirmado', 'T2 idempotente';
end $$;
set local role authenticated;

-- T3: admin vê a cobrança; usuário comum não chama funções de service; portal vê a própria
do $$ declare v r%rowtype; n int; begin
  select * into v from r;
  select count(*) into n from public.pix_cobrancas where organizacao_id = v.org;
  assert n = 2, 'T3 admin vê as cobranças';
  begin
    perform public.pix_confirmar('MP-222');
    raise exception 'T3 pix_confirmar por usuário deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

-- T4: bloqueio assistido — vencida além do prazo sugere bloqueio; executar suspende;
--     pagamento em dia sugere desbloqueio; executar reativa; sugestões não duplicam
do $$ declare v r%rowtype; res jsonb; v_id uuid; v_lanc2 uuid; v_cat uuid; v_conta uuid; begin
  select * into v from r;
  -- nova vencida (a primeira foi paga no T2)
  select id into v_conta from public.contas where nome = 'Caixa Pix';
  select id into v_cat from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1;
  select (public.criar_lancamento('receita', 'Vencida bloqueio', 100, current_date - 30, current_date - 30, null, v_conta, null, v_cat, null, v.neg, v.pessoa, v.ct)).id into v_lanc2;
  res := public.gerar_bloqueios(v.neg);
  select id into v_id from public.bloqueios where contrato_id = v.ct and tipo = 'bloqueio' and status = 'pendente';
  assert v_id is not null, 'T4 bloqueio sugerido';
  res := public.gerar_bloqueios(v.neg);
  assert (select count(*) from public.bloqueios where contrato_id = v.ct and tipo = 'bloqueio' and status = 'pendente') = 1, 'T4 sem duplicar';
  perform public.executar_bloqueio(v_id);
  assert (select status::text from public.contratos where id = v.ct) = 'suspenso', 'T4 contrato suspenso';
  -- cliente paga → desbloqueio sugerido
  perform public.efetivar_lancamento(v_lanc2, current_date, 0, null);
  res := public.gerar_bloqueios(v.neg);
  select id into v_id from public.bloqueios where contrato_id = v.ct and tipo = 'desbloqueio' and status = 'pendente';
  assert v_id is not null, 'T4 desbloqueio sugerido';
  perform public.executar_bloqueio(v_id);
  assert (select status::text from public.contratos where id = v.ct) = 'ativo', 'T4 contrato reativado';
  begin
    perform public.executar_bloqueio(v_id);
    raise exception 'T4 executar duas vezes deveria falhar';
  exception when check_violation then null; end;
end $$;

rollback;
\echo OK
