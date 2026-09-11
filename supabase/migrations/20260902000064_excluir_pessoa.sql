-- =============================================================================
-- 0064 · Excluir pessoa sem histórico
-- =============================================================================
-- Botão "Excluir" no cadastro de pessoas. Só exclui quem NÃO tem histórico:
-- qualquer contrato, lançamento, OS, comodato, técnico etc. segura a exclusão
-- (chave estrangeira) e a função devolve um erro amigável — nesses casos o
-- caminho continua sendo desativar. Vínculos "de cadastro" (vínculo com
-- negócio, acesso ao portal e o login do portal) são removidos junto.
-- Sem grant de DELETE nas tabelas: a exclusão só passa por esta função.
-- =============================================================================

create function public.excluir_pessoa(p_pessoa_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pessoa public.pessoas%rowtype;
  v_auth uuid[];
begin
  select * into v_pessoa from public.pessoas where id = p_pessoa_id;
  if not found then
    raise exception 'Pessoa não encontrada.' using errcode = 'no_data_found';
  end if;
  perform public.exigir_membro(v_pessoa.organizacao_id);

  -- vínculos de cadastro saem junto; histórico (FK) barra a exclusão
  select coalesce(array_agg(usuario_id), '{}') into v_auth
    from public.portal_acessos where pessoa_id = p_pessoa_id and usuario_id is not null;

  begin
    delete from public.portal_acessos where pessoa_id = p_pessoa_id;
    delete from public.pessoa_negocio_vinculos where pessoa_id = p_pessoa_id;
    delete from public.pessoas where id = p_pessoa_id;
  exception when foreign_key_violation then
    raise exception 'Esta pessoa tem histórico (contratos, lançamentos, OS, comodato…) e não pode ser excluída. Desative-a.' using errcode = 'check_violation';
  end;

  -- login do portal fica órfão sem a pessoa: remove também
  if array_length(v_auth, 1) > 0 then
    delete from auth.users where id = any(v_auth);
  end if;
end;
$$;
revoke all on function public.excluir_pessoa(uuid) from public, anon;
grant execute on function public.excluir_pessoa(uuid) to authenticated;
