-- =============================================================================
-- 0086 · EXCLUIR ITEM DE ESTOQUE SEM MOVIMENTAÇÃO — item 44 do levantamento
-- =============================================================================
-- "Quero ter a opção de editar o que criei, excluir." Item criado na hora
-- (ex.: pela Nova compra ou pelo lançamento) e nunca movimentado — nasce
-- zerado e continua zerado até a 1ª entrada. Se nunca teve movimentação,
-- comodato, instalação, uso em campanha ou devolução, pode ser excluído.
-- Histórico real (qualquer FK) barra a exclusão — desative em vez disso.
-- =============================================================================
create function public.excluir_estoque_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_item public.estoque_itens%rowtype;
begin
  select * into v_item from public.estoque_itens where id = p_item_id;
  if not found then raise exception 'Item não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(v_item.organizacao_id);
  if v_item.quantidade_atual <> 0 then
    raise exception 'Item tem saldo em estoque: dê saída ou ajuste para zero antes de excluir.' using errcode = 'check_violation';
  end if;

  begin
    delete from public.estoque_itens where id = p_item_id;
  exception when foreign_key_violation then
    raise exception 'Este item já foi movimentado (compra, instalação, comodato…) e não pode ser excluído. Desative-o em vez disso.' using errcode = 'check_violation';
  end;
end;
$$;
revoke all on function public.excluir_estoque_item(uuid) from public, anon;
grant execute on function public.excluir_estoque_item(uuid) to authenticated;
