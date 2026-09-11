-- Testes da migration 0060 (BI gerencial). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_p1 uuid; v_p2 uuid; v_plano uuid; v_conta uuid; v_cat uuid; v_ct uuid; v_l uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'BI T', 'bi-t', true) returning id into v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'BI Cliente 1') returning id into v_p1;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'BI Cliente 2') returning id into v_p2;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'BI Plano', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'BI Caixa', 'dinheiro', v_neg) returning id into v_conta;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  -- contrato antigo (ativo desde 3 meses atrás) e um encerrado no mês passado
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p1, v_plano, 100, 'mensal', (date_trunc('month', current_date) - interval '3 months')::date, 10, v_conta) returning id into v_ct;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p2, v_plano, 200, 'mensal', (date_trunc('month', current_date) - interval '3 months')::date, 10, v_conta) returning id into v_l;
  update public.contratos set status = 'encerrado', data_fim = (date_trunc('month', current_date) - interval '1 month')::date + 5 where id = v_l;
  -- mês corrente: uma cobrança paga e uma vencida em aberto
  perform public.criar_lancamento('receita', 'BI paga', 100, date_trunc('month', current_date)::date + 1, date_trunc('month', current_date)::date + 1, date_trunc('month', current_date)::date + 1, v_conta, null, v_cat, null, v_neg, v_p1, v_ct);
  if date_trunc('month', current_date)::date + 2 < current_date then
    perform public.criar_lancamento('receita', 'BI vencida', 100, date_trunc('month', current_date)::date + 2, date_trunc('month', current_date)::date + 2, null, v_conta, null, v_cat, null, v_neg, v_p1, v_ct);
  end if;
end $$;

do $$ declare v_neg uuid; r record; m record; begin
  select id into v_neg from public.negocios where slug = 'bi-t';
  -- mês passado: cancelamento conta no churn; início com 2 ativos
  select * into r from public.vw_bi_mensal_negocio where negocio_id = v_neg and mes = to_char(date_trunc('month', current_date) - interval '1 month', 'YYYY-MM');
  assert r.cancelamentos = 1 and r.ativos_inicio = 2 and r.churn_pct = 50.0, 'T1 churn do mês passado: ' || r.churn_pct;
  assert r.ativos_fim = 1 and r.mrr = 100 and r.ticket_medio = 100, 'T1 mrr/ticket após cancelamento';
  -- mês corrente: receitas do mês
  select * into m from public.vw_bi_mensal_negocio where negocio_id = v_neg and mes = to_char(current_date, 'YYYY-MM');
  assert m.recebido = 100, 'T2 recebido no mês: ' || m.recebido;
  assert m.previsto >= 100, 'T2 previsto no mês';
  if current_date > date_trunc('month', current_date)::date + 2 then
    assert m.vencido_aberto = 100 and m.inadimplencia_pct = 50.0, 'T2 inadimplência: ' || m.inadimplencia_pct;
  end if;
  -- 13 meses por negócio
  assert (select count(*) from public.vw_bi_mensal_negocio where negocio_id = v_neg) = 13, 'T3 13 meses';
end $$;

rollback;
\echo OK
