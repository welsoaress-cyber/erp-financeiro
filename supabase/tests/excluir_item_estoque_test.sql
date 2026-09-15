-- Testes da migration 0086 (excluir item de estoque sem movimentação). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_cat uuid; v_item uuid; v_item2 uuid; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'EXC T', 'exc-t', true) returning id into v_neg;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Equip EXC') returning id into v_cat;

  -- T1: item nunca movimentado (zerado) é excluído
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome) values (v_org, v_neg, v_cat, 'EXC-01', 'Item exclui') returning id into v_item;
  perform public.excluir_estoque_item(v_item);
  if exists (select 1 from public.estoque_itens where id = v_item) then raise exception 'T1 item não foi excluído'; end if;

  -- T2: item com saldo não é excluído
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome) values (v_org, v_neg, v_cat, 'EXC-02', 'Item com saldo') returning id into v_item2;
  perform public.entrada_estoque(v_item2, 5, 100);
  begin
    perform public.excluir_estoque_item(v_item2);
    raise exception 'T2 deveria falhar (tem saldo)';
  exception when others then null; end;
  if not exists (select 1 from public.estoque_itens where id = v_item2) then raise exception 'T2 item não deveria ter sido excluído'; end if;

  -- T3: item zerado mas com histórico (já teve entrada e saída) não é excluído
  perform public.saida_estoque(v_item2, 5, 'perda');
  if (select quantidade_atual from public.estoque_itens where id = v_item2) <> 0 then raise exception 'T3 setup: saldo deveria ser 0'; end if;
  begin
    perform public.excluir_estoque_item(v_item2);
    raise exception 'T3 deveria falhar (tem histórico de movimentação)';
  exception when others then null; end;
  if not exists (select 1 from public.estoque_itens where id = v_item2) then raise exception 'T3 item não deveria ter sido excluído'; end if;

  -- T4: item inexistente
  begin
    perform public.excluir_estoque_item(gen_random_uuid());
    raise exception 'T4 deveria falhar (não encontrado)';
  exception when others then null; end;
end $$;

rollback;
\echo OK
