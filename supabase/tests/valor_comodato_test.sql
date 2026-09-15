-- Testes da migration 0084 (valor em comodato no relatório de estoque). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_cat uuid; v_item uuid; v_p uuid; v_plano uuid; v_ct uuid; r record; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'VC T', 'vc-t', true) returning id into v_neg;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Equip VC') returning id into v_cat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome) values (v_org, v_neg, v_cat, 'ONU-VC', 'ONU VC') returning id into v_item;
  perform public.entrada_estoque(v_item, 4, 480); -- custo médio 120
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente VC', '92988881111') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano VC', 100, 'mensal') returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, faturamento_automatico)
  values (v_org, v_neg, v_p, v_plano, 100, 'mensal', current_date, 10, false) returning id into v_ct;

  -- T1: sem comodato, valor_comodato = 0 e valor_estoque cheio
  select * into r from public.vw_rel_estoque_itens where item_id = v_item;
  if r.em_comodato <> 0 or r.valor_comodato <> 0 or r.valor_estoque <> 480 then raise exception 'T1 %', to_jsonb(r); end if;

  -- T2: dois comodatos instalados → valor_comodato = 2 × custo médio
  perform public.registrar_comodato(v_neg, v_item, 'SN-VC-001', v_p, v_ct, null);
  perform public.registrar_comodato(v_neg, v_item, 'SN-VC-002', v_p, v_ct, null);
  select * into r from public.vw_rel_estoque_itens where item_id = v_item;
  if r.em_comodato <> 2 or r.valor_comodato <> 240 then raise exception 'T2 em_comodato=% valor=%', r.em_comodato, r.valor_comodato; end if;

  -- T3: perda de um comodato tira do valor em comodato
  perform public.perda_comodato((select id from public.comodatos where numero_serie = 'SN-VC-002' and item_id = v_item), 'Cliente perdeu');
  select * into r from public.vw_rel_estoque_itens where item_id = v_item;
  if r.em_comodato <> 1 or r.valor_comodato <> 120 then raise exception 'T3 em_comodato=% valor=%', r.em_comodato, r.valor_comodato; end if;
end $$;

rollback;
\echo OK
