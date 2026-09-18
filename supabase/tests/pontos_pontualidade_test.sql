-- Testes das migrations 0100/0101 (pontos por pontualidade, etapa 58A — sem teto, campanha até 30/09/2027). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg_on uuid; v_neg_off uuid; v_p1 uuid; v_plano uuid; v_plano_off uuid;
  v_conta uuid; v_conta_off uuid; v_ct_principal uuid; v_ct_sva uuid; v_ct_off uuid; v_cat uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'PONTOS ON', 'pontos-on', true) returning id into v_neg_on;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'PONTOS OFF', 'pontos-off', true) returning id into v_neg_off;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, pontos_ativo) values (v_org, v_neg_on, '+5592999990101', true, true);
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, pontos_ativo) values (v_org, v_neg_off, '+5592999990102', true, false);

  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Pontual', '92988887001') returning id into v_p1;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg_on, 'Plano Pontos', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Pontos', 'dinheiro', v_neg_on) returning id into v_conta;

  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg_on, v_p1, v_plano, 100, 'mensal', current_date - 90, 20, v_conta, 'ativo') returning id into v_ct_principal;
  -- contrato adicional/SVA da mesma pessoa: marcado não elegível
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status, elegivel_pontos)
  values (v_org, v_neg_on, v_p1, v_plano, 20, 'mensal', current_date - 90, 20, v_conta, 'ativo', false) returning id into v_ct_sva;
  -- mesmo cenário, no negócio com o programa desligado
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg_off, 'Plano Pontos Off', 100, 'mensal') returning id into v_plano_off;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Pontos Off', 'dinheiro', v_neg_off) returning id into v_conta_off;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg_off, v_p1, v_plano_off, 100, 'mensal', current_date - 90, 20, v_conta_off, 'ativo') returning id into v_ct_off;

  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;

  -- T1: pago 10 dias antes (venc 20/10, pago 10/10) → 11 pontos
  perform public.criar_lancamento('receita', 'Fatura 10 dias antes', 100, '2026-10-01', '2026-10-20', null,
    v_conta, null, v_cat, null, v_neg_on, v_p1, v_ct_principal);
  -- T2: pago no vencimento → 1 ponto
  perform public.criar_lancamento('receita', 'Fatura no vencimento', 100, '2026-10-01', '2026-10-20', null,
    v_conta, null, v_cat, null, v_neg_on, v_p1, v_ct_principal);
  -- T3: pago depois do vencimento → 0 pontos (sem registro)
  perform public.criar_lancamento('receita', 'Fatura atrasada', 100, '2026-10-01', '2026-10-20', null,
    v_conta, null, v_cat, null, v_neg_on, v_p1, v_ct_principal);
  -- T4: pago bem adiantado → sem teto, 39 dias antes = 40 pontos
  perform public.criar_lancamento('receita', 'Fatura super adiantada', 100, '2026-11-01', '2026-11-20', null,
    v_conta, null, v_cat, null, v_neg_on, v_p1, v_ct_principal);
  -- T12: pago adiantado mas DEPOIS do fim da campanha (30/09/2027) → sem pontos
  perform public.criar_lancamento('receita', 'Fatura depois da campanha', 100, '2027-10-01', '2027-10-20', null,
    v_conta, null, v_cat, null, v_neg_on, v_p1, v_ct_principal);
  -- T5: contrato SVA (não elegível) pago bem adiantado → sem pontos
  perform public.criar_lancamento('receita', 'Fatura SVA adiantada', 20, '2026-10-01', '2026-10-20', null,
    v_conta, null, v_cat, null, v_neg_on, v_p1, v_ct_sva);
  -- T6: negócio com pontos desligado, pago adiantado → sem pontos
  perform public.criar_lancamento('receita', 'Fatura negócio sem programa', 100, '2026-10-01', '2026-10-20', null,
    v_conta_off, null, v_cat, null, v_neg_off, v_p1, v_ct_off);
  -- T7: pago adiantado mas ANTES da vigência (01/10/2026) → sem pontos
  perform public.criar_lancamento('receita', 'Fatura antes da vigência', 100, '2026-09-01', '2026-09-25', null,
    v_conta, null, v_cat, null, v_neg_on, v_p1, v_ct_principal);
  -- T8/T9: fatura que será reagendada e depois estornada
  perform public.criar_lancamento('receita', 'Fatura reagendada', 100, '2026-12-01', '2026-12-20', null,
    v_conta, null, v_cat, null, v_neg_on, v_p1, v_ct_principal);
end $$;

create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='pontos-on') neg_on,
  (select id from public.contratos where pessoa_id = (select id from public.pessoas where nome='Cliente Pontual') and elegivel_pontos and negocio_id = (select id from public.negocios where slug='pontos-on') and valor = 100) ct_principal,
  (select id from public.lancamentos where descricao = 'Fatura 10 dias antes') l_10dias,
  (select id from public.lancamentos where descricao = 'Fatura no vencimento') l_no_dia,
  (select id from public.lancamentos where descricao = 'Fatura atrasada') l_atrasada,
  (select id from public.lancamentos where descricao = 'Fatura super adiantada') l_teto,
  (select id from public.lancamentos where descricao = 'Fatura SVA adiantada') l_sva,
  (select id from public.lancamentos where descricao = 'Fatura negócio sem programa') l_sem_programa,
  (select id from public.lancamentos where descricao = 'Fatura antes da vigência') l_antes_vigencia,
  (select id from public.lancamentos where descricao = 'Fatura depois da campanha') l_depois_campanha,
  (select id from public.lancamentos where descricao = 'Fatura reagendada') l_reagendada;

-- efetiva cada uma na data certa pro cenário
do $$ declare v r%rowtype; begin
  select * into v from r;
  perform public.efetivar_lancamento(v.l_10dias, '2026-10-10');
  perform public.efetivar_lancamento(v.l_no_dia, '2026-10-20');
  perform public.efetivar_lancamento(v.l_atrasada, '2026-10-21');
  perform public.efetivar_lancamento(v.l_teto, '2026-10-12'); -- 40 dias antes de 20/11
  perform public.efetivar_lancamento(v.l_sva, '2026-10-10');
  perform public.efetivar_lancamento(v.l_sem_programa, '2026-10-10');
  perform public.efetivar_lancamento(v.l_antes_vigencia, '2026-09-15');
  perform public.efetivar_lancamento(v.l_depois_campanha, '2027-10-05'); -- pago adiantado (venc. 20/10), mas depois do fim da campanha
  -- reagendamento no mesmo mês não muda o vencimento original, e fica auditado
  perform public.atualizar_lancamento(v.l_reagendada, 'Fatura reagendada', 100, '2026-12-01', '2026-12-27', null);
end $$;

-- T1: 10 dias antes → 11 pontos
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select pontos from public.pontos_pontualidade where lancamento_id = v.l_10dias) = 11, 'T1 10 dias antes = 11 pontos';
end $$;

-- T2: no vencimento → 1 ponto (nunca punido)
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select pontos from public.pontos_pontualidade where lancamento_id = v.l_no_dia) = 1, 'T2 no vencimento = 1 ponto';
end $$;

-- T3: atrasado → sem registro
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert not exists (select 1 from public.pontos_pontualidade where lancamento_id = v.l_atrasada), 'T3 atrasado não gera pontos';
end $$;

-- T4: super adiantado → sem teto, 39 dias antes = 40 pontos
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select pontos from public.pontos_pontualidade where lancamento_id = v.l_teto) = 40, 'T4 sem teto: 39 dias antes = 40 pontos';
end $$;

-- T5/T6/T7/T12: casos que não pontuam por regra de elegibilidade/opt-in/janela da campanha
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert not exists (select 1 from public.pontos_pontualidade where lancamento_id = v.l_sva), 'T5 contrato SVA não pontua';
  assert not exists (select 1 from public.pontos_pontualidade where lancamento_id = v.l_sem_programa), 'T6 negócio sem programa não pontua';
  assert not exists (select 1 from public.pontos_pontualidade where lancamento_id = v.l_antes_vigencia), 'T7 antes de 01/10/2026 não pontua';
  assert not exists (select 1 from public.pontos_pontualidade where lancamento_id = v.l_depois_campanha), 'T12 depois de 30/09/2027 não pontua';
end $$;

-- T8: saldo do cliente no negócio soma T1+T2+T4 (11+1+40=52), pelo saldo de vw_saldo_pontos
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select saldo from public.vw_saldo_pontos where pessoa_id = (select id from public.pessoas where nome='Cliente Pontual') and negocio_id = v.neg_on and ciclo_inicio = '2026-10-01') = 52,
    'T8 saldo soma os contratos elegíveis do ciclo';
end $$;

-- T9: reagendamento não mexe no vencimento original, mas fica auditado
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select data_vencimento_original from public.lancamentos where id = v.l_reagendada) = '2026-12-20',
    'T9 vencimento original intocado após reagendar';
  assert (select data_vencimento from public.lancamentos where id = v.l_reagendada) = '2026-12-27',
    'T9 vencimento atual foi reagendado';
  assert exists (select 1 from public.lancamentos_vencimento_historico where lancamento_id = v.l_reagendada and vencimento_anterior = '2026-12-20' and vencimento_novo = '2026-12-27'),
    'T9 histórico de reagendamento gravado';
end $$;

-- T10: estorno remove os pontos daquela fatura
do $$ declare v r%rowtype; begin
  select * into v from r;
  perform public.estornar_lancamento(v.l_10dias, 'Pagamento em duplicidade, corrigindo.');
  assert not exists (select 1 from public.pontos_pontualidade where lancamento_id = v.l_10dias), 'T10 estorno remove os pontos';
end $$;

-- T11: contrato encerrado no meio do ciclo perde o saldo do negócio
do $$ declare v r%rowtype; begin
  select * into v from r;
  update public.contratos set status = 'encerrado', data_fim = current_date where id = v.ct_principal;
  assert not exists (select 1 from public.vw_saldo_pontos where pessoa_id = (select id from public.pessoas where nome='Cliente Pontual') and negocio_id = v.neg_on and ciclo_inicio = '2026-10-01'),
    'T11 contrato encerrado zera o saldo do ciclo';
end $$;

rollback;
\echo OK
