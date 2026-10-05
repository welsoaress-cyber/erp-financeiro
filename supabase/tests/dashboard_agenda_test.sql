-- Testes da migration 0125 (vw_dashboard_agenda — Agenda Financeira do dashboard). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_rec uuid; v_desp uuid; r record; begin
  select organizacao_id into v_org from public.categorias limit 1;
  select id into v_rec from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  select id into v_desp from public.categorias where organizacao_id = v_org and tipo = 'despesa' limit 1;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Caixa Agenda', 'dinheiro') returning id into v_conta;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'Agenda T', 'agenda-t', true) returning id into v_neg;

  -- vencida (não deve aparecer na agenda — fica em Pendências)
  perform public.criar_lancamento('receita', 'Vencida', 10, current_date - 5, current_date - 5, null, v_conta, null, v_rec, null, v_neg);
  -- hoje
  perform public.criar_lancamento('receita', 'Hoje rec', 20, current_date, current_date, null, v_conta, null, v_rec, null, v_neg);
  perform public.criar_lancamento('despesa', 'Hoje desp', 5, current_date, current_date, null, v_conta, null, v_desp, null, v_neg);
  -- 7 dias (amanhã..+7)
  perform public.criar_lancamento('receita', '7dias rec', 30, current_date + 3, current_date + 3, null, v_conta, null, v_rec, null, v_neg);
  -- 30 dias (+8..+30)
  perform public.criar_lancamento('despesa', '30dias desp', 15, current_date + 15, current_date + 15, null, v_conta, null, v_desp, null, v_neg);
  -- acima de 30 dias
  perform public.criar_lancamento('receita', 'Mais30 rec', 40, current_date + 45, current_date + 45, null, v_conta, null, v_rec, null, v_neg);
  -- efetivado não deve entrar (só previstos)
  perform public.criar_lancamento('receita', 'Efetivada hoje', 999, current_date, current_date, current_date, v_conta, null, v_rec, null, v_neg);
  -- cancelado não deve entrar
  perform public.cancelar_lancamento((public.criar_lancamento('despesa', 'Cancelada', 999, current_date, current_date, null, v_conta, null, v_desp, null, v_neg)).id, 'teste');

  if exists (select 1 from public.vw_dashboard_agenda where negocio_id = v_neg and valor = 10) then raise exception 'T1 vencida não deveria aparecer'; end if;
  if exists (select 1 from public.vw_dashboard_agenda where negocio_id = v_neg and valor = 999) then raise exception 'T1 efetivada/cancelada não deveriam aparecer'; end if;

  select * into r from public.vw_dashboard_agenda where negocio_id = v_neg and tipo = 'receita' and bucket = 'hoje';
  if r.valor <> 20 then raise exception 'T2 hoje receita=%', r.valor; end if;
  select * into r from public.vw_dashboard_agenda where negocio_id = v_neg and tipo = 'despesa' and bucket = 'hoje';
  if r.valor <> 5 then raise exception 'T2 hoje despesa=%', r.valor; end if;

  select * into r from public.vw_dashboard_agenda where negocio_id = v_neg and tipo = 'receita' and bucket = '7dias';
  if r.valor <> 30 then raise exception 'T3 7dias=%', r.valor; end if;

  select * into r from public.vw_dashboard_agenda where negocio_id = v_neg and tipo = 'despesa' and bucket = '30dias';
  if r.valor <> 15 then raise exception 'T4 30dias=%', r.valor; end if;

  select * into r from public.vw_dashboard_agenda where negocio_id = v_neg and tipo = 'receita' and bucket = 'mais30';
  if r.valor <> 40 then raise exception 'T5 mais30=%', r.valor; end if;

  if (select count(*) from public.vw_dashboard_agenda where negocio_id = v_neg) <> 5 then raise exception 'T6 total de linhas inesperado'; end if;
end $$;

rollback;
\echo OK
