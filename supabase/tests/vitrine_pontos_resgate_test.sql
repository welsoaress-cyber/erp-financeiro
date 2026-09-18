-- Testes da migration 0102 (vitrine de prêmios + resgate de pontos, etapa 58B). Saída "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values ('99999999-9999-9999-9999-999999999999', 'pontos-cliente@teste.dev', '{"portal":"true"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_p1 uuid; v_plano uuid; v_conta uuid; v_cat uuid; v_item uuid; v_ct uuid; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'PONTOS RESGATE', 'pontos-resgate', true) returning id into v_neg;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, pontos_ativo) values (v_org, v_neg, '+5592999990201', true, true);
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Resgate', '92988889001') returning id into v_p1;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Resgate', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Resgate', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg, v_p1, v_plano, 100, 'mensal', current_date - 90, 20, v_conta, 'ativo') returning id into v_ct;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Brindes') returning id into v_cat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_cat, 'BR-CANECA', 'Caneca Servnet', 'unidade') returning id into v_item;
  perform public.ajuste_estoque(v_item, 3, 30, 'custo 10 — estoque inicial');
end $$;

create temp table r as select
  (select id from public.negocios where slug='pontos-resgate') neg,
  (select id from public.pessoas where nome='Cliente Resgate') p1,
  (select id from public.contratos where pessoa_id = (select id from public.pessoas where nome='Cliente Resgate')) ct,
  (select id from public.estoque_itens where codigo='BR-CANECA') item,
  (select id from public.categorias where organizacao_id = (select organizacao_id from public.negocios where slug='pontos-resgate') and tipo = 'receita' limit 1) cat;
grant select on r to service_role;

-- T1: cadastro do prêmio calcula pontos_custo = ceil(valor / 0,22)
do $$ declare v r%rowtype; pr public.pontos_premios%rowtype; begin
  select * into v from r;
  insert into public.pontos_premios (organizacao_id, negocio_id, nome, item_id, valor_reais)
  values ((select organizacao_id from public.negocios where id = v.neg), v.neg, 'Caneca Servnet', v.item, 2.20)
  returning * into pr;
  assert pr.pontos_custo = 10, 'T1 pontos_custo = ceil(2.20/0.22) = 10, veio ' || pr.pontos_custo;
end $$;

-- T2: prêmio fora da categoria Brindes é rejeitado
do $$ declare v r%rowtype; v_org uuid; v_cat2 uuid; v_item2 uuid; begin
  select * into v from r; select organizacao_id into v_org from public.negocios where id = v.neg;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v.neg, 'Cabos') returning id into v_cat2;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v.neg, v_cat2, 'CB-01', 'Cabo de rede', 'metro') returning id into v_item2;
  begin
    insert into public.pontos_premios (organizacao_id, negocio_id, nome, item_id, valor_reais) values (v_org, v.neg, 'Cabo', v_item2, 5);
    raise exception 'T2 item fora de Brindes deveria falhar';
  exception when check_violation then null; end;
end $$;

-- gera pontos pro cliente: pagou 9 dias antes do vencimento (10/10) em 01/10 → 10 pontos
do $$ declare v r%rowtype; l public.lancamentos%rowtype; begin
  select * into v from r;
  l := public.criar_lancamento('receita', 'Fatura pontos resgate', 100, '2026-10-01', '2026-10-10', null,
    (select conta_id from public.contratos where id = v.ct), null, v.cat, null, v.neg, v.p1, v.ct);
  perform public.efetivar_lancamento(l.id, '2026-10-01');
end $$;

-- T3: sem vínculo no portal, resgatar falha (saldo de quem não está logado = 0 aqui, sem pessoa)
reset role;
do $$ declare v r%rowtype; begin
  select * into v from r;
  perform public.portal_vincular_servico(v.p1, '99999999-9999-9999-9999-999999999999');
end $$;
set local role authenticated;
set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';

-- T4: vitrine mostra o prêmio cadastrado com saldo em estoque
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select count(*) from public.portal_pontos_vitrine(v.neg)) = 1, 'T4 vitrine mostra 1 prêmio';
  assert (select saldo from public.portal_pontos_saldo() where negocio_id = v.neg) = 10, 'T4 saldo inicial = 10 pontos';
end $$;

-- T5: resgata o prêmio (10 pontos), saldo zera, fica pendente de entrega
do $$ declare v r%rowtype; pr uuid; res public.pontos_resgates%rowtype; begin
  select * into v from r;
  select id into pr from public.portal_pontos_vitrine(v.neg) limit 1;
  res := public.portal_resgatar_premio_pontos(pr);
  assert res.pontos = 10 and res.entregue_em is null, 'T5 resgate criado, aguardando entrega';
  assert coalesce((select saldo from public.portal_pontos_saldo() where negocio_id = v.neg), 0) = 0, 'T5 saldo zerado após resgate';
  begin
    perform public.portal_resgatar_premio_pontos(pr);
    raise exception 'T5 resgatar sem saldo deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T6: admin entrega — baixa 1 do estoque (origem resgate_pontos), sem repetir
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; res_id uuid; q numeric; begin
  select * into v from r;
  select id into res_id from public.pontos_resgates where pessoa_id = v.p1 and tipo = 'brinde';
  perform public.entregar_premio_pontos(res_id, 'Entregue na loja');
  select quantidade_atual into q from public.estoque_itens where id = v.item;
  assert q = 2, 'T6 baixou 1 unidade (3 - 1 = 2)';
  assert exists (select 1 from public.estoque_movimentacoes where item_id = v.item and origem = 'resgate_pontos'), 'T6 movimentação resgate_pontos';
  begin
    perform public.entregar_premio_pontos(res_id, null);
    raise exception 'T6 entregar duas vezes deveria falhar';
  exception when check_violation then null; end;
end $$;

-- gera mais pontos com 2 faturas JÁ PAGAS bem adiantado (não são as que vamos descontar)
do $$ declare v r%rowtype; g1 public.lancamentos%rowtype; g2 public.lancamentos%rowtype; begin
  select * into v from r;
  g1 := public.criar_lancamento('receita', 'Fatura geradora de pontos 1', 100, '2026-11-01', '2026-11-20', null,
    (select conta_id from public.contratos where id = v.ct), null, v.cat, null, v.neg, v.p1, v.ct);
  perform public.efetivar_lancamento(g1.id, '2026-11-01'); -- 19 dias antes = 20 pontos
  g2 := public.criar_lancamento('receita', 'Fatura geradora de pontos 2', 100, '2026-12-01', '2026-12-20', null,
    (select conta_id from public.contratos where id = v.ct), null, v.cat, null, v.neg, v.p1, v.ct);
  perform public.efetivar_lancamento(g2.id, '2026-12-01'); -- 19 dias antes = 20 pontos
end $$;

-- 2 faturas EM ABERTO (previsto) pra receber o desconto: a pequena (100%) vence primeiro, a grande (parcial) depois
-- — a função sempre pega a fatura em aberto de vencimento mais próximo, então a ordem dos testes segue a ordem de vencimento
do $$ declare v r%rowtype; begin
  select * into v from r;
  perform public.criar_lancamento('receita', 'Fatura desconto total', 3, '2027-01-01', '2027-01-20', null,
    (select conta_id from public.contratos where id = v.ct), null, v.cat, null, v.neg, v.p1, v.ct);
  perform public.criar_lancamento('receita', 'Fatura desconto parcial', 50, '2027-02-01', '2027-02-20', null,
    (select conta_id from public.contratos where id = v.ct), null, v.cat, null, v.neg, v.p1, v.ct);
end $$;

-- T7: desconto parcial — abaixo do mínimo de 4 pontos falha
set local role authenticated;
set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select saldo from public.portal_pontos_saldo() where negocio_id = v.neg) = 40, 'T7 saldo = 20+20 = 40 pontos';
  begin
    perform public.portal_resgatar_desconto_pontos(v.neg, 3);
    raise exception 'T7 menos de 4 pontos deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T8: resgate de 100% de uma fatura pequena (R$ 3, 12 pontos = R$ 3,00, a de vencimento mais próximo) cancela a fatura (cortesia)
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table v_fatura_t8 as select id from public.lancamentos where descricao = 'Fatura desconto total';
set local role authenticated;
set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
do $$ declare v r%rowtype; begin
  select * into v from r;
  perform public.portal_resgatar_desconto_pontos(v.neg, 12);
end $$;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ begin
  assert (select status from public.lancamentos where id = (select id from v_fatura_t8)) = 'cancelado', 'T8 fatura 100% descontada vira cancelada (cortesia)';
end $$;

-- T9: resgata 8 pontos (R$ 2,00) na próxima fatura em aberto (R$ 50) — reduz o valor, sem zerar
create temp table v_fatura_t9 as select id from public.lancamentos where descricao = 'Fatura desconto parcial';
set local role authenticated;
set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
do $$ declare v r%rowtype; res public.pontos_resgates%rowtype; begin
  select * into v from r;
  res := public.portal_resgatar_desconto_pontos(v.neg, 8);
  assert res.pontos = 8 and res.valor_reais = 2.00, 'T9 8 pontos = R$ 2,00';
end $$;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ begin
  assert (select valor from public.lancamentos where id = (select id from v_fatura_t9)) = 48.00, 'T9 fatura de 50 caiu pra 48';
  assert (select status from public.lancamentos where id = (select id from v_fatura_t9)) = 'previsto', 'T9 fatura continua previsto (não zerou)';
end $$;

-- T10: relatório de resgates mostra os 3 resgates (brinde entregue + 2 descontos)
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select count(*) from public.vw_rel_pontos_resgates where negocio_id = v.neg) = 3, 'T10 relatório com os 3 resgates';
  assert (select count(*) from public.vw_rel_pontos_resgates where negocio_id = v.neg and situacao = 'Entregue') = 1, 'T10 um entregue';
  assert (select count(*) from public.vw_rel_pontos_resgates where negocio_id = v.neg and situacao = 'Aplicado') = 2, 'T10 dois descontos aplicados';
end $$;

rollback;
\echo OK
