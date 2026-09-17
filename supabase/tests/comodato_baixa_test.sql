-- Testes da migration 0091 (comodato baixa e devolve estoque com simetria). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$
declare
  v_org uuid; v_neg uuid; v_cat uuid; v_item uuid; v_pes uuid; v_conta uuid;
  c public.comodatos%rowtype; v_saldo numeric;
begin
  select id into v_org from public.organizacoes limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'COMOD BX', 'comod-bx', true) returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Comod', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Equip') returning id into v_cat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida)
    values (v_org, v_neg, v_cat, 'ONU-BX', 'ONU teste', 'unidade') returning id into v_item;
  insert into public.pessoas (organizacao_id, nome, tipo) values (v_org, 'Cliente Comodato', 'fisica') returning id into v_pes;
  perform public.entrada_estoque(v_item, 10, 1000, current_date, 'compra', null, 'Compra ONU');

  -- T1: registro normal TIRA do estoque
  c := public.registrar_comodato(v_neg, v_item, 'SN-0001', v_pes, null, null);
  select quantidade_atual into v_saldo from public.estoque_itens where id = v_item;
  assert v_saldo = 9 and c.baixou_estoque, 'T1 registro baixa o estoque';
  assert exists (select 1 from public.estoque_movimentacoes where item_id = v_item and tipo = 'saida' and observacao like '%SN-0001%'), 'T1 movimentação de saída registrada';

  -- T2: recolher devolve (saiu, então volta)
  perform public.recolher_comodato(c.id, false, 'Cliente cancelou');
  select quantidade_atual into v_saldo from public.estoque_itens where id = v_item;
  assert v_saldo = 10, 'T2 recolhimento devolve o que saiu';

  -- T3: equipamento legado NÃO baixa
  c := public.registrar_comodato(v_neg, v_item, 'SN-LEGADO', v_pes, null, 'Já estava na casa do cliente', false);
  select quantidade_atual into v_saldo from public.estoque_itens where id = v_item;
  assert v_saldo = 10 and not c.baixou_estoque, 'T3 legado não baixa o estoque';

  -- T4: recolher o legado NÃO infla o estoque (era o bug)
  perform public.recolher_comodato(c.id, false, 'Recolhido');
  select quantidade_atual into v_saldo from public.estoque_itens where id = v_item;
  assert v_saldo = 10, 'T4 recolher legado não infla o saldo';

  -- T5: série duplicada não mexe no estoque
  c := public.registrar_comodato(v_neg, v_item, 'SN-0002', v_pes, null, null);
  select quantidade_atual into v_saldo from public.estoque_itens where id = v_item;
  begin
    perform public.registrar_comodato(v_neg, v_item, 'SN-0002', v_pes, null, null);
    raise exception 'T5 série duplicada deveria falhar';
  exception when check_violation then null; end;
  assert (select quantidade_atual from public.estoque_itens where id = v_item) = v_saldo, 'T5 falha de série não mexe no estoque';

  -- T6: descarte não devolve, mesmo tendo saído
  perform public.recolher_comodato(c.id, true, 'Queimado, descartado');
  assert (select quantidade_atual from public.estoque_itens where id = v_item) = v_saldo, 'T6 descarte não devolve';

  -- T7: estoque insuficiente barra o registro
  update public.estoque_itens set quantidade_atual = 0 where id = v_item;
  begin
    perform public.registrar_comodato(v_neg, v_item, 'SN-0009', v_pes, null, null);
    raise exception 'T7 sem estoque deveria falhar';
  exception when check_violation then null; end;
  -- e o legado continua passando mesmo com estoque zerado
  c := public.registrar_comodato(v_neg, v_item, 'SN-0010', v_pes, null, 'Legado', false);
  assert not c.baixou_estoque, 'T7 legado passa sem estoque';
end $$;

rollback;
\echo OK
