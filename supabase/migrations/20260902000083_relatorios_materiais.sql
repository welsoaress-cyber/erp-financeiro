-- =============================================================================
-- 0083 · RELATÓRIOS DE MATERIAIS — 53C (parcial): estoque e alocação em clientes
-- =============================================================================
-- Pedido: "lista de materiais e apontamento para cliente, se tiver alocado".
-- Duas views derivadas (security_invoker), no padrão da Central de Relatórios:
-- 1) vw_rel_estoque_itens — saldo, custo médio, valor em estoque, mínimo, situação.
-- 2) vw_rel_materiais_cliente — o que está com cliente: comodato instalado
--    (série, cliente, contrato, desde) + saídas por instalação (movimentações).
-- =============================================================================
create view public.vw_rel_estoque_itens
with (security_invoker = true) as
select i.organizacao_id, i.negocio_id, coalesce(n.nome, '—') as negocio,
       i.id as item_id, i.codigo, i.nome as item, c.nome as categoria, i.unidade_medida,
       i.marca, i.modelo, i.localizacao, i.ativo,
       i.quantidade_atual, i.quantidade_minima,
       i.valor_custo as custo_medio,
       round(i.quantidade_atual * i.valor_custo, 2)::numeric(14,2) as valor_estoque,
       case when not i.ativo then 'inativo'
            when i.quantidade_atual <= 0 then 'zerado'
            when i.quantidade_minima > 0 and i.quantidade_atual < i.quantidade_minima then 'abaixo_minimo'
            else 'ok' end as situacao,
       (select count(*) from public.comodatos k where k.item_id = i.id and k.status = 'instalado')::int as em_comodato
  from public.estoque_itens i
  join public.estoque_categorias c on c.id = i.categoria_id
  left join public.negocios n on n.id = i.negocio_id;
grant select on public.vw_rel_estoque_itens to authenticated;

create view public.vw_rel_materiais_cliente
with (security_invoker = true) as
select k.organizacao_id, k.negocio_id, coalesce(n.nome, '—') as negocio,
       'comodato'::text as tipo, k.status::text as situacao,
       i.id as item_id, i.nome as item, k.numero_serie,
       1::numeric(12,2) as quantidade,
       k.pessoa_id, p.nome as pessoa, p.telefone,
       k.contrato_id, ct.codigo as contrato_codigo,
       k.data_instalacao as data,
       round(i.valor_custo, 2)::numeric(12,2) as valor
  from public.comodatos k
  join public.estoque_itens i on i.id = k.item_id
  join public.pessoas p on p.id = k.pessoa_id
  left join public.contratos ct on ct.id = k.contrato_id
  left join public.negocios n on n.id = k.negocio_id
union all
select m.organizacao_id, m.negocio_id, coalesce(n.nome, '—'),
       'instalacao', 'consumido',
       i.id, i.nome, null,
       m.quantidade,
       m.pessoa_id, p.nome, p.telefone,
       m.contrato_id, ct.codigo,
       m.data,
       round(m.valor_total, 2)
  from public.estoque_movimentacoes m
  join public.estoque_itens i on i.id = m.item_id
  left join public.pessoas p on p.id = m.pessoa_id
  left join public.contratos ct on ct.id = m.contrato_id
  left join public.negocios n on n.id = m.negocio_id
 where m.tipo = 'saida' and m.origem = 'instalacao' and (m.pessoa_id is not null or m.contrato_id is not null);
grant select on public.vw_rel_materiais_cliente to authenticated;
