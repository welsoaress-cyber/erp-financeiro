-- Testes da migration 0133 (encerramento automático por inadimplência). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg_enc uuid; v_neg_sem uuid; v_p1 uuid; v_p2 uuid; v_p3 uuid; v_plano uuid;
  v_conta uuid; v_ct1 uuid; v_ct2 uuid; v_ct3 uuid; v_cat uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'ENC AUTO', 'enc-auto', true) returning id into v_neg_enc;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'ENC OFF', 'enc-off', true) returning id into v_neg_sem;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, dias_apos, encerramento_automatico, encerramento_apos_dias)
    values (v_org, v_neg_enc, '+5592999990011', true, 5, true, 10);
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, dias_apos, encerramento_automatico)
    values (v_org, v_neg_sem, '+5592999990012', true, 5, false);

  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Vencido Longo', '92988887001') returning id into v_p1;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Vencido Curto', '92988887002') returning id into v_p2;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Negocio Sem Robo', '92988887003') returning id into v_p3;

  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg_enc, 'Plano Enc', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Enc', 'dinheiro', v_neg_enc) returning id into v_conta;

  -- ct1: suspenso, vencido há 20 dias (> 10 configurado) → deve encerrar
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg_enc, v_p1, v_plano, 100, 'mensal', current_date - 90, 10, v_conta, 'suspenso') returning id into v_ct1;
  -- ct2: suspenso, vencido há só 3 dias (< 10 configurado) → não deve encerrar ainda
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg_enc, v_p2, v_plano, 100, 'mensal', current_date - 90, 10, v_conta, 'suspenso') returning id into v_ct2;

  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg_sem, 'Plano Sem Robo', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Sem Robo', 'dinheiro', v_neg_sem) returning id into v_conta;
  -- ct3: mesmo cenário do ct1, mas no negócio SEM encerramento_automatico → não pode mexer sozinho
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg_sem, v_p3, v_plano, 100, 'mensal', current_date - 90, 10, v_conta, 'suspenso') returning id into v_ct3;

  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  perform public.criar_lancamento('receita', 'Vencida longa', 100, current_date - 20, current_date - 20, null,
    (select conta_id from public.contratos where id = v_ct1), null, v_cat, null, v_neg_enc, v_p1, v_ct1);
  perform public.criar_lancamento('receita', 'Vencida curta', 100, current_date - 3, current_date - 3, null,
    (select conta_id from public.contratos where id = v_ct2), null, v_cat, null, v_neg_enc, v_p2, v_ct2);
  perform public.criar_lancamento('receita', 'Vencida sem robo', 100, current_date - 20, current_date - 20, null,
    (select conta_id from public.contratos where id = v_ct3), null, v_cat, null, v_neg_sem, v_p3, v_ct3);
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='enc-auto') neg_enc,
  (select id from public.negocios where slug='enc-off') neg_sem,
  (select id from public.contratos where pessoa_id = (select id from public.pessoas where nome='Cliente Vencido Longo')) ct1,
  (select id from public.contratos where pessoa_id = (select id from public.pessoas where nome='Cliente Vencido Curto')) ct2,
  (select id from public.contratos where pessoa_id = (select id from public.pessoas where nome='Cliente Negocio Sem Robo')) ct3;
grant select on r to service_role;

set local role service_role; -- simula o robô diário (sem sessão de usuário)

-- T1: o contrato vencido há mais que o prazo configurado encerra sozinho, com motivo preenchido
do $$ declare v r%rowtype; res jsonb; begin
  select * into v from r;
  res := public.executar_encerramentos_automaticos();
  assert (res->>'encerrados')::int = 1, 'T1 encerrou exatamente um contrato: ' || res;
  assert (select status from public.contratos where id = v.ct1) = 'encerrado', 'T1 contrato vencido há muito tempo foi encerrado';
  assert (select motivo_encerramento from public.contratos where id = v.ct1) is not null, 'T1 motivo de encerramento preenchido';
end $$;

-- T2: o contrato vencido há menos tempo que o prazo não é mexido
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select status from public.contratos where id = v.ct2) = 'suspenso', 'T2 contrato recente continua suspenso';
end $$;

-- T3: a cobrança vencida do contrato encerrado virou perda (cancelada)
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select status from public.lancamentos where contrato_id = v.ct1 and tipo = 'receita') = 'cancelado', 'T3 cobrança vencida virou perda';
end $$;

-- T4: negócio SEM encerramento_automatico não é tocado
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select status from public.contratos where id = v.ct3) = 'suspenso', 'T4 negócio sem o robô ligado não é mexido';
end $$;

-- T5: rodar de novo não refaz nem duplica (contrato já encerrado some da condição)
do $$ declare res jsonb; begin
  res := public.executar_encerramentos_automaticos();
  assert (res->>'encerrados')::int = 0, 'T5 rodar de novo não repete o que já foi encerrado: ' || res;
end $$;

-- T6: o robô diário geral (bloqueio + curso + encerramento) continua rodando sem erro
do $$ declare res jsonb; begin
  res := public.executar_bloqueios_automaticos();
  assert res ? 'encerrados', 'T6 robô diário geral inclui a chave "encerrados": ' || res;
end $$;

-- T7: relatório mostra o contrato encerrado, com telefone
set local role authenticated;
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert exists (select 1 from public.vw_rel_encerramentos_inadimplencia where id = v.ct1 and telefone = '92988887001'), 'T7 relatório com o cliente e telefone certos';
  assert not exists (select 1 from public.vw_rel_encerramentos_inadimplencia where id = v.ct2), 'T7 contrato não encerrado não aparece no relatório';
end $$;

rollback;
\echo OK
