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

-- T4: vw_rel_lancamentos resolve nomes; vw_rel_inadimplencia só previstos vencidos
do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat uuid; v_p uuid; v_id uuid; begin
  select organizacao_id into v_org from public.categorias limit 1;
  select id into v_neg from public.negocios where slug = 'cc-t';
  select id into v_conta from public.contas where nome = 'Caixa CC';
  select id into v_cat from public.categorias where nome = 'CC Receita';
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente CC', '92988887777') returning id into v_p;
  v_id := (public.criar_lancamento('receita', 'CC vencida', 70, current_date - 20, current_date - 20, null, v_conta, null, v_cat, null, v_neg, v_p)).id;
  perform public.criar_lancamento('receita', 'CC no prazo', 30, current_date, current_date + 5, null, v_conta, null, v_cat, null, v_neg, v_p);
  if (select negocio || '|' || pessoa || '|' || categoria || '|' || conta from public.vw_rel_lancamentos where id = v_id) <> 'CC T|Cliente CC|CC Receita|Caixa CC' then raise exception 'T4 nomes'; end if;
  if (select count(*) from public.vw_rel_inadimplencia where negocio_id = v_neg) <> 1 then raise exception 'T4 inadimplência'; end if;
  if (select dias_atraso from public.vw_rel_inadimplencia where id = v_id) <> 20 then raise exception 'T4 dias'; end if;
end $$;

-- T5: favoritos são do usuário; remover só via função
do $$ declare v_org uuid; v_id uuid; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.relatorios_favoritos (organizacao_id, relatorio, nome, filtros) values (v_org, 'centro-custo', 'Fechamento', '{"mes":"2026-09"}') returning id into v_id;
  if (select usuario_id from public.relatorios_favoritos where id = v_id) <> '11111111-1111-1111-1111-111111111111' then raise exception 'T5 usuario'; end if;
  -- delete direto: sem policy de delete, a RLS não apaga nada (localmente o shim concede privilégios amplos)
  begin
    delete from public.relatorios_favoritos where id = v_id;
  exception when insufficient_privilege then null; end;
  if not exists (select 1 from public.relatorios_favoritos where id = v_id) then raise exception 'T5 delete direto apagou'; end if;
  perform public.remover_relatorio_favorito(v_id);
  if exists (select 1 from public.relatorios_favoritos where id = v_id) then raise exception 'T5 não removeu'; end if;
  begin
    perform public.remover_relatorio_favorito(v_id);
    raise exception 'T5 remover inexistente deveria falhar';
  exception when no_data_found then null; end;
end $$;

rollback;
\echo OK
