-- Testes da migration 0072 (voto de confiança na Cobrança). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_p uuid; v_plano uuid; v_conta uuid; v_ct uuid; v_cat uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'CONF T', 'conf-t', true) returning id into v_neg;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, dias_apos) values (v_org, v_neg, '+5592999990002', true, 5);
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Confiança', '92988885555') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Conf', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Conf', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p, v_plano, 100, 'mensal', current_date - 60, 10, v_conta) returning id into v_ct;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  perform public.criar_lancamento('receita', 'Vencida conf', 100, current_date - 30, current_date - 30, null, v_conta, null, v_cat, null, v_neg, v_p, v_ct);
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='conf-t') neg,
  (select id from public.pessoas where nome='Cliente Confiança') pessoa,
  (select c.id from public.contratos c join public.negocios n on n.id=c.negocio_id where n.slug='conf-t') ct,
  (select id from public.lancamentos where descricao='Vencida conf') lanc;

-- T1: confiança segura o bloqueio — pendente é descartado e não volta enquanto ativa
do $$ declare v r%rowtype; conf public.confiancas%rowtype; begin
  select * into v from r;
  perform public.gerar_bloqueios(v.neg);
  assert exists (select 1 from public.bloqueios where contrato_id = v.ct and tipo = 'bloqueio' and status = 'pendente' and not confianca_furada), 'T1 bloqueio sugerido sem destaque';
  conf := public.dar_confianca(v.ct, current_date + 7, 'Prometeu pagar dia tal');
  assert conf.status = 'ativa' and conf.segurar_ate = current_date + 7, 'T1 confiança ativa';
  assert not exists (select 1 from public.bloqueios where contrato_id = v.ct and status = 'pendente'), 'T1 pendente descartado na hora';
  perform public.gerar_bloqueios(v.neg);
  assert not exists (select 1 from public.bloqueios where contrato_id = v.ct and status = 'pendente'), 'T1 confiança segura o bloqueio';
end $$;

-- T2: validações e substituição
do $$ declare v r%rowtype; conf public.confiancas%rowtype; begin
  select * into v from r;
  begin
    perform public.dar_confianca(v.ct, current_date, null);
    raise exception 'T2 data de hoje deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.dar_confianca(v.ct, current_date + 120, null);
    raise exception 'T2 mais de 90 dias deveria falhar';
  exception when check_violation then null; end;
  conf := public.dar_confianca(v.ct, current_date + 10, null);
  assert (select count(*) from public.confiancas where contrato_id = v.ct and status = 'ativa') = 1, 'T2 só uma ativa';
  assert (select count(*) from public.confiancas where contrato_id = v.ct and status = 'cancelada') = 1, 'T2 anterior cancelada';
end $$;

-- T3: prazo venceu devendo → furada; bloqueio volta destacado
reset role;
update public.confiancas set segurar_ate = current_date - 1 where status = 'ativa' and contrato_id = (select ct from r);
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; begin
  select * into v from r;
  perform public.gerar_bloqueios(v.neg);
  assert exists (select 1 from public.confiancas where contrato_id = v.ct and status = 'furada'), 'T3 confiança furada';
  assert not exists (select 1 from public.confiancas where contrato_id = v.ct and status = 'ativa'), 'T3 nenhuma ativa restante';
  assert exists (select 1 from public.bloqueios where contrato_id = v.ct and tipo = 'bloqueio' and status = 'pendente' and confianca_furada), 'T3 bloqueio destacado';
end $$;

-- T4: nova confiança + pagamento dentro do prazo → cumprida; próxima dívida volta sem destaque
do $$ declare v r%rowtype; conf public.confiancas%rowtype; v_cat uuid; v_conta uuid; begin
  select * into v from r;
  conf := public.dar_confianca(v.ct, current_date + 5, null);
  perform public.efetivar_lancamento(v.lanc, current_date, 0, null);
  perform public.gerar_bloqueios(v.neg);
  assert (select status::text from public.confiancas where id = conf.id) = 'cumprida', 'T4 confiança cumprida';
  assert not exists (select 1 from public.bloqueios where contrato_id = v.ct and status = 'pendente'), 'T4 nada pendente';
  begin
    perform public.cancelar_confianca(conf.id);
    raise exception 'T4 cancelar cumprida deveria falhar';
  exception when check_violation then null; end;
  -- nova dívida depois da cumprida: sugere bloqueio SEM destaque (a furada é antiga)
  select id into v_conta from public.contas where nome = 'Caixa Conf';
  select id into v_cat from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1;
  perform public.criar_lancamento('receita', 'Vencida conf 2', 100, current_date - 20, current_date - 20, null, v_conta, null, v_cat, null, v.neg, v.pessoa, v.ct);
  perform public.gerar_bloqueios(v.neg);
  assert exists (select 1 from public.bloqueios where contrato_id = v.ct and tipo = 'bloqueio' and status = 'pendente' and not confianca_furada), 'T4 volta sem destaque';
end $$;

rollback;
\echo OK
