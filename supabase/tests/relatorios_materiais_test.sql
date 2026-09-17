-- Testes da migration 0083 (relatórios de materiais). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_cat uuid; v_item uuid; v_p uuid; v_plano uuid; v_ct uuid; r record; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'MAT T', 'mat-t', true) returning id into v_neg;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Equip MAT') returning id into v_cat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, quantidade_minima) values (v_org, v_neg, v_cat, 'ROT-MAT', 'Roteador MAT', 2) returning id into v_item;
  perform public.entrada_estoque(v_item, 3, 300);
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente MAT', '92988880000') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano MAT', 100, 'mensal') returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, faturamento_automatico)
  values (v_org, v_neg, v_p, v_plano, 100, 'mensal', current_date, 10, false) returning id into v_ct;

  -- T1: lista de estoque
  select * into r from public.vw_rel_estoque_itens where item_id = v_item;
  if r.quantidade_atual <> 3 or r.custo_medio <> 100 or r.valor_estoque <> 300 or r.situacao <> 'ok' or r.categoria <> 'Equip MAT' then raise exception 'T1 %', to_jsonb(r); end if;

  -- T2: comodato instalado aparece alocado ao cliente e o saldo cai (0091: entregar baixa o estoque)
  perform public.registrar_comodato(v_neg, v_item, 'SN-MAT-001', v_p, v_ct, null);
  select * into r from public.vw_rel_materiais_cliente where item_id = v_item and tipo = 'comodato';
  if r.pessoa <> 'Cliente MAT' or r.numero_serie <> 'SN-MAT-001' or r.situacao <> 'instalado' then raise exception 'T2 %', to_jsonb(r); end if;
  select * into r from public.vw_rel_estoque_itens where item_id = v_item;
  if r.em_comodato <> 1 then raise exception 'T2 em_comodato=%', r.em_comodato; end if;

  -- T3: saída por instalação com contrato aparece como consumido
  perform public.saida_estoque(v_item, 1, 'instalacao', current_date, v_p, v_ct, 'cabo');
  if (select count(*) from public.vw_rel_materiais_cliente where item_id = v_item and tipo = 'instalacao' and contrato_id = v_ct) <> 1 then raise exception 'T3 instalação'; end if;
  -- 3 comprados − 1 do comodato − 1 da instalação = 1, abaixo do mínimo (2).
  -- O bem em comodato continua sendo da empresa, mas não está mais na prateleira:
  -- quem mostra o que está na casa dos clientes é em_comodato/valor_comodato.
  select * into r from public.vw_rel_estoque_itens where item_id = v_item;
  if r.quantidade_atual <> 1 or r.situacao <> 'abaixo_minimo' then raise exception 'T3 saldo=% situacao=%', r.quantidade_atual, r.situacao; end if;
  if r.em_comodato <> 1 then raise exception 'T3 em_comodato=%', r.em_comodato; end if;
  perform public.saida_estoque(v_item, 1, 'instalacao', current_date, v_p, v_ct, 'cabo 2');
  select * into r from public.vw_rel_estoque_itens where item_id = v_item;
  if r.quantidade_atual <> 0 or r.situacao <> 'zerado' then raise exception 'T3b saldo=% situacao=%', r.quantidade_atual, r.situacao; end if;
end $$;

rollback;
\echo OK
