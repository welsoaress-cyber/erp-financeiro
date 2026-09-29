-- Bug: vw_rel_compras_requisicoes_pendentes (0092) é security_invoker e faz
-- left join direto em auth.users — RLS bloqueia authenticated ali (nem o
-- proprietário tem select nessa tabela), então o relatório dava "Você não
-- tem permissão para esta operação" pra todo mundo, sempre.
-- Corrige com uma função security definer só pra resolver o nome (não abre
-- a tabela inteira; mesma organização de quem já pode ver a requisição).
create or replace function public.nome_usuario(p_usuario_id uuid)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(u.raw_user_meta_data->>'nome', u.email, 'Usuário')
    from auth.users u
   where u.id = p_usuario_id;
$$;
revoke all on function public.nome_usuario(uuid) from public, anon;
grant execute on function public.nome_usuario(uuid) to authenticated;

create or replace view public.vw_rel_compras_requisicoes_pendentes with (security_invoker = true) as
select r.organizacao_id,
       r.id as requisicao_id,
       r.numero,
       n.nome as negocio,
       r.criado_em::date as data,
       coalesce(public.nome_usuario(r.solicitante_id), 'Solicitante') as solicitante,
       r.justificativa,
       (select count(*) from public.compra_requisicao_itens i where i.requisicao_id = r.id) as itens,
       (select sum(quantidade) from public.compra_requisicao_itens i where i.requisicao_id = r.id) as quantidade_total
  from public.compra_requisicoes r
  join public.negocios n on n.id = r.negocio_id
 where r.status = 'pendente';
grant select on public.vw_rel_compras_requisicoes_pendentes to authenticated;
