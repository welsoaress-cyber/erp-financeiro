-- Testes da migration 0079 (relatório por centro de custo). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_rec uuid; v_op uuid; v_inv uuid; v_mes date := date_trunc('month', current_date)::date; r record; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'CC T', 'cc-t', true) returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Caixa CC', 'dinheiro') returning id into v_conta;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'CC Receita', 'receita') returning id into v_rec;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'CC Energia', 'despesa') returning id into v_op;
  insert into public.categorias (organizacao_id, nome, tipo, natureza) values (v_org, 'CC Equipamento', 'despesa', 'investimento') returning id into v_inv;
  -- efetivados: receita 500, despesa op 120, investimento 300; previsto: despesa op 80; cancelado não entra
  perform public.criar_lancamento('receita', 'CC rec', 500, v_mes, v_mes, v_mes, v_conta, null, v_rec, null, v_neg);
  perform public.criar_lancamento('despesa', 'CC energia', 120, v_mes, v_mes, v_mes, v_conta, null, v_op, null, v_neg);
  perform public.criar_lancamento('despesa', 'CC equip', 300, v_mes, v_mes, v_mes, v_conta, null, v_inv, null, v_neg);
  perform public.criar_lancamento('despesa', 'CC energia prev', 80, v_mes, v_mes, null, v_conta, null, v_op, null, v_neg);
  perform public.cancelar_lancamento((public.criar_lancamento('despesa', 'CC cancelado', 999, v_mes, v_mes, null, v_conta, null, v_op, null, v_neg)).id, 'teste');

  -- T1: totais realizados por natureza
  select coalesce(sum(valor) filter (where tipo = 'receita'), 0) as rec,
         coalesce(sum(valor) filter (where tipo = 'despesa' and natureza = 'operacional'), 0) as op,
         coalesce(sum(valor) filter (where tipo = 'despesa' and natureza = 'investimento'), 0) as inv
    into r from public.vw_centro_custo_mensal where negocio_id = v_neg and mes = v_mes and status = 'efetivado';
  if r.rec <> 500 or r.op <> 120 or r.inv <> 300 then raise exception 'T1 rec=% op=% inv=%', r.rec, r.op, r.inv; end if;
  -- T2: previsto separado; cancelado fora
  if (select sum(valor) from public.vw_centro_custo_mensal where negocio_id = v_neg and mes = v_mes and status = 'previsto') <> 80 then raise exception 'T2 previsto'; end if;
  if exists (select 1 from public.vw_centro_custo_mensal where negocio_id = v_neg and valor >= 999) then raise exception 'T2 cancelado entrou'; end if;
  -- T3: detalhe por categoria
  if (select valor from public.vw_centro_custo_mensal where negocio_id = v_neg and mes = v_mes and status = 'efetivado' and categoria = 'CC Energia') <> 120 then raise exception 'T3 categoria'; end if;
end $$;

rollback;
\echo OK
