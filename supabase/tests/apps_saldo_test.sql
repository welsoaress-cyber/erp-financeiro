-- Testes da migration 0013 (saldo para ativação de apps). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco', 'corrente' from ids;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Carteira Digital', 'carteira_digital' from ids;
insert into public.negocios (organizacao_id, nome, slug) select org, 'Ativação de App', 'apps' from ids;
insert into public.negocios (organizacao_id, nome, slug) select org, 'Créditos', 'creditos' from ids;
insert into public.pessoas (organizacao_id, nome, documento) select org, 'Cliente A', '52998224725' from ids;
create temp table r as select (select org from ids) org,
  (select id from public.contas where nome='Banco') banco, (select id from public.contas where nome='Carteira Digital') cart,
  (select id from public.negocios where slug='apps') apps, (select id from public.negocios where slug='creditos') cred,
  (select id from public.pessoas where nome='Cliente A') cliente,
  (select id from public.categorias where nome='Salário') cat_rec, (select id from public.categorias where nome='Outros' and tipo='despesa') cat_desp;

-- T1: configuração do negócio e da carteira; regras
do $$ declare v r%rowtype; w public.carteira; begin
  select * into v from r;
  begin
    perform public.configurar_carteira(v.apps, v.cart, v.cat_desp);
    raise exception 'T1 sem tipo_saldo deveria falhar';
  exception when check_violation then null; end;
  begin
    update public.negocios set tipo_saldo = 'credito' where id = v.cred;
    raise exception 'T1 crédito sem taxa deveria falhar';
  exception when check_violation then null; end;
  update public.negocios set tipo_saldo = 'dinheiro', conta_padrao_id = v.banco, categoria_receita_id = v.cat_rec where id = v.apps;
  update public.negocios set tipo_saldo = 'credito', taxa_conversao = 0.1, conta_padrao_id = v.banco, categoria_receita_id = v.cat_rec where id = v.cred;
  begin
    perform public.configurar_carteira(v.apps, v.cart, v.cat_rec);
    raise exception 'T1 categoria de receita como consumo deveria falhar';
  exception when check_violation then null; end;
  w := public.configurar_carteira(v.apps, v.cart, v.cat_desp);
  assert w.saldo = 0 and w.conta_id = v.cart, 'T1 carteira criada zerada';
  w := public.configurar_carteira(v.cred, v.cart, v.cat_desp);
  begin
    insert into public.carteira (organizacao_id, negocio_id, conta_id, categoria_consumo_id) values (v.org, v.apps, v.cart, v.cat_desp);
    raise exception 'T1 insert direto na carteira deveria falhar';
  exception when insufficient_privilege or unique_violation then null; end;
end $$;

-- T2: catálogo — criar_app cria plano anual; update sincroniza plano; insert direto bloqueado
do $$ declare v r%rowtype; a public.apps_catalogo; pl public.planos; begin
  select * into v from r;
  a := public.criar_app(v.apps, 'NINJA PLAYER', 13, 120);
  select * into pl from public.planos where id = a.plano_id;
  assert pl.nome = 'NINJA PLAYER' and pl.periodicidade = 'anual' and pl.valor_tabela = 120 and pl.negocio_id = v.apps, 'T2 plano do app';
  update public.apps_catalogo set nome = 'Ninja Player', custo = 15 where id = a.id;
  assert (select nome from public.planos where id = a.plano_id) = 'Ninja Player', 'T2 nome sincronizado com o plano';
  begin
    perform public.criar_app(v.apps, 'ninja player', 1, 1);
    raise exception 'T2 nome duplicado deveria falhar';
  exception when unique_violation then null; end;
  begin
    insert into public.apps_catalogo (organizacao_id, negocio_id, plano_id, nome, custo) values (v.org, v.apps, pl.id, 'X', 1);
    raise exception 'T2 insert direto deveria falhar';
  exception when insufficient_privilege or unique_violation then null; end;
  perform public.criar_app(v.cred, 'NINJA PLAYER', 1.2, 100);
end $$;

-- T3: modo dinheiro — recarga 100 (transferência) e ativação 13 → saldo 87; contrato anual; receita prevista; despesa efetivada
do $$ declare v r%rowtype; t public.transacoes_carteira; c public.contratos; a uuid; n int; begin
  select * into v from r;
  select id into a from public.apps_catalogo where negocio_id = v.apps;
  begin
    perform public.ativar_app(v.apps, v.cliente, a, current_date);
    raise exception 'T3 ativar sem saldo deveria falhar';
  exception when check_violation then assert sqlerrm like 'Saldo insuficiente%', 'T3 msg: ' || sqlerrm; end;
  t := public.recarregar_carteira(v.apps, 100, v.banco, current_date, 'primeira recarga');
  assert t.tipo = 'recarga' and t.valor = 100 and t.valor_reais = 100 and t.lancamento_id is not null, 'T3 recarga';
  assert (select saldo from public.carteira where negocio_id = v.apps) = 100, 'T3 saldo 100';
  assert (select tipo from public.lancamentos where id = t.lancamento_id) = 'transferencia', 'T3 recarga é transferência banco → carteira';
  assert (select saldo from public.vw_saldo_contas where id = v.cart) = 100 and (select saldo from public.vw_saldo_contas where id = v.banco) = -100, 'T3 dinheiro moveu para a conta da carteira';
  c := public.ativar_app(v.apps, v.cliente, a, current_date, null, null, 'cliente A');
  assert c.status = 'ativo' and c.periodicidade = 'anual' and c.valor = 120 and c.pessoa_id = v.cliente and c.faturamento_automatico, 'T3 contrato de anuidade';
  assert (select saldo from public.carteira where negocio_id = v.apps) = 85, 'T3 saldo 100 − 15 (custo atualizado) = 85';
  select count(*) into n from public.lancamentos where contrato_id = c.id and tipo = 'receita' and status = 'previsto' and valor = 120 and origem = 'faturamento'; assert n = 1, 'T3 receita da anuidade prevista via faturamento';
  select count(*) into n from public.faturamentos where contrato_id = c.id; assert n = 1, 'T3 registrada em faturamentos (não duplica)';
  select count(*) into n from public.lancamentos where contrato_id = c.id and tipo = 'despesa' and status = 'efetivado' and valor = 15 and conta_id = v.cart and categoria_id = v.cat_desp and origem = 'sistema'; assert n = 1, 'T3 despesa do consumo vinculada ao contrato';
  assert (select saldo from public.vw_saldo_contas where id = v.cart) = 85, 'T3 conta da carteira = saldo da carteira';
  assert (select count(*) from public.transacoes_carteira where negocio_id = v.apps and tipo = 'consumo' and contrato_id = c.id and app_id = a) = 1, 'T3 transação de consumo';
  -- faturamento diário não duplica a anuidade
  perform public.gerar_faturamento_agora(current_date + 30);
  select count(*) into n from public.lancamentos where contrato_id = c.id and tipo = 'receita'; assert n = 1, 'T3 faturamento não duplica';
  -- resumo
  assert (select saldo from public.vw_carteira_resumo where negocio_id = v.apps) = 85, 'T3 resumo saldo';
  assert (select (total_recargas, total_consumos, apps_ativos, anuidades_ativas) from public.vw_carteira_resumo where negocio_id = v.apps) = (100::numeric, 15::numeric, 1::bigint, 120::numeric), 'T3 resumo totais';
  assert (select situacao from public.vw_contratos_app where contrato_id = c.id) = 'ativo', 'T3 situação ativo';
end $$;

-- T4: modo créditos — R$ 50 → 5 créditos; ativação 1,2 → 3,8; despesa R$ 12
do $$ declare v r%rowtype; t public.transacoes_carteira; c public.contratos; a uuid; begin
  select * into v from r;
  select id into a from public.apps_catalogo where negocio_id = v.cred;
  t := public.recarregar_carteira(v.cred, 50, v.banco, date '2026-09-02');
  assert t.valor = 5 and t.valor_reais = 50, 'T4 50 reais = 5 créditos';
  c := public.ativar_app(v.cred, v.cliente, a, date '2026-09-02');
  assert (select saldo from public.carteira where negocio_id = v.cred) = 3.8, 'T4 saldo 3,8 créditos';
  assert (select valor from public.lancamentos where contrato_id = c.id and tipo = 'despesa') = 12, 'T4 consumo de 1,2 créditos = R$ 12';
  assert (select valor_reais from public.transacoes_carteira where contrato_id = c.id) = 12, 'T4 contrapartida em reais';
  assert (select saldo from public.vw_saldo_contas where id = v.cart) = 85 + 50 - 12, 'T4 conta carteira consolida os dois negócios';
end $$;

-- T5: imutabilidade — sem update/delete em transações; saldo nunca negativo; anon negado; situação vencido
do $$ declare v r%rowtype; c uuid; begin
  select * into v from r;
  begin
    update public.transacoes_carteira set valor = 1 where negocio_id = v.apps;
    raise exception 'T5 update deveria falhar';
  exception when insufficient_privilege or check_violation then null; end;
  begin
    delete from public.transacoes_carteira where negocio_id = v.apps;
    raise exception 'T5 delete deveria falhar';
  exception when insufficient_privilege or check_violation then null; end;
  begin
    update public.carteira set saldo = 999 where negocio_id = v.apps;
    raise exception 'T5 update direto no saldo deveria falhar';
  exception when insufficient_privilege then null; end;
  -- vencido: anuidade prevista com vencimento no passado (ativação de 02/09/2026 no negócio de créditos)
  select contrato_id into c from public.vw_contratos_app where negocio_id = v.cred limit 1;
  assert (select situacao from public.vw_contratos_app where contrato_id = c) = 'vencido', 'T5 anuidade vencida → vencido';
  assert (select proximo_vencimento from public.vw_contratos_app where contrato_id = c) = date '2026-09-02', 'T5 próximo vencimento';
end $$;
set local role anon;
do $$ begin
  begin
    perform public.recarregar_carteira(gen_random_uuid(), 10, gen_random_uuid());
    raise exception 'T5 anon deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
\echo OK
