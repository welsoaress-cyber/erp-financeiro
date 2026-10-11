-- Testes da migration 0136 (promessa de pagamento em cobrança avulsa, sem contrato). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_p uuid; v_conta uuid; v_cat uuid; v_cat_desp uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'CONF LANC T', 'conf-lanc-t', true) returning id into v_neg;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Avulso', '92988884444') returning id into v_p;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Avulso', 'dinheiro', v_neg) returning id into v_conta;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  select id into v_cat_desp from public.categorias where organizacao_id = v_org and tipo = 'despesa' limit 1;
  -- cobrança avulsa (sem contrato): ativação de app, por exemplo
  perform public.criar_lancamento('receita', 'Ativação App', 30, current_date, current_date + 5, null, v_conta, null, v_cat, null, v_neg, v_p, null);
  perform public.criar_lancamento('despesa', 'Conta avulsa', 50, current_date, current_date + 5, null, v_conta, null, v_cat_desp, null, v_neg, v_p, null);
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='conf-lanc-t') neg,
  (select id from public.pessoas where nome='Cliente Avulso') pessoa,
  (select id from public.lancamentos where descricao='Ativação App') lanc,
  (select id from public.lancamentos where descricao='Conta avulsa') lanc_despesa;
grant select on r to service_role;

-- T1: promessa sobre lançamento sem contrato funciona e fica ativa
do $$ declare v r%rowtype; conf public.confiancas%rowtype; begin
  select * into v from r;
  conf := public.dar_confianca_lancamento(v.lanc, current_date + 7, 'Prometeu pagar dia tal');
  assert conf.status = 'ativa' and conf.contrato_id is null and conf.lancamento_id = v.lanc, 'T1 promessa avulsa ativa, sem contrato';
end $$;

-- T2: validações — despesa, lançamento não previsto, data inválida
do $$ declare v r%rowtype; begin
  select * into v from r;
  begin
    perform public.dar_confianca_lancamento(v.lanc_despesa, current_date + 7, null);
    raise exception 'T2 despesa deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.dar_confianca_lancamento(v.lanc, current_date, null);
    raise exception 'T2 data de hoje deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.dar_confianca_lancamento(v.lanc, current_date + 120, null);
    raise exception 'T2 mais de 90 dias deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: nova chamada substitui a anterior (só uma ativa por lançamento)
do $$ declare v r%rowtype; conf public.confiancas%rowtype; begin
  select * into v from r;
  conf := public.dar_confianca_lancamento(v.lanc, current_date + 10, null);
  assert (select count(*) from public.confiancas where lancamento_id = v.lanc and status = 'ativa') = 1, 'T3 só uma ativa';
  assert (select count(*) from public.confiancas where lancamento_id = v.lanc and status = 'cancelada') = 1, 'T3 anterior cancelada';
end $$;

-- T4: pagar o lançamento resolve a promessa sozinha (cumprida)
do $$ declare v r%rowtype; conf_id uuid; begin
  select * into v from r;
  select id into conf_id from public.confiancas where lancamento_id = v.lanc and status = 'ativa';
  perform public.efetivar_lancamento(v.lanc, current_date, 0, null);
  assert (select status::text from public.confiancas where id = conf_id) = 'cumprida', 'T4 promessa cumprida ao pagar';
end $$;

-- T5: baixa parcial também resolve a promessa do lançamento original
do $$ declare v r%rowtype; v_lanc2 uuid; conf_id uuid; begin
  select * into v from r;
  perform public.criar_lancamento('receita', 'Ativação App 2', 40, current_date, current_date + 5, null,
    (select id from public.contas where nome = 'Caixa Avulso'), null,
    (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1), null, v.neg, v.pessoa, null);
  select id into v_lanc2 from public.lancamentos where descricao = 'Ativação App 2';
  conf_id := (public.dar_confianca_lancamento(v_lanc2, current_date + 7, null)).id;
  perform public.baixar_parcial(v_lanc2, 20, current_date);
  assert (select status::text from public.confiancas where id = conf_id) = 'cumprida', 'T5 promessa cumprida na baixa parcial';
end $$;

-- T6: cancelar o lançamento também resolve a promessa (moot)
do $$ declare v r%rowtype; v_lanc3 uuid; conf_id uuid; begin
  select * into v from r;
  perform public.criar_lancamento('receita', 'Ativação App 3', 25, current_date, current_date + 5, null,
    (select id from public.contas where nome = 'Caixa Avulso'), null,
    (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1), null, v.neg, v.pessoa, null);
  select id into v_lanc3 from public.lancamentos where descricao = 'Ativação App 3';
  conf_id := (public.dar_confianca_lancamento(v_lanc3, current_date + 7, null)).id;
  perform public.cancelar_lancamento(v_lanc3, 'Desistiu');
  assert (select status::text from public.confiancas where id = conf_id) = 'cumprida', 'T6 promessa resolvida ao cancelar';
end $$;

rollback;
\echo OK
