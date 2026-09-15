-- =============================================================================
-- 0084 · VALOR EM COMODATO NO RELATÓRIO DE ESTOQUE (item 39 do levantamento)
-- =============================================================================
-- Pedido: "custo de mercadoria em estoque ou em comodato" — o relatório de
-- estoque mostrava o comodato só como contagem. Acrescenta valor_comodato
-- (unidades instaladas × custo médio) para fechar a visão capital em
-- prateleira × capital na rua. Recria a view (create or replace preserva
-- colunas; a nova entra no fim).
-- =============================================================================
create or replace view public.vw_rel_estoque_itens
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
       (select count(*) from public.comodatos k where k.item_id = i.id and k.status = 'instalado')::int as em_comodato,
       round((select count(*) from public.comodatos k where k.item_id = i.id and k.status = 'instalado') * i.valor_custo, 2)::numeric(14,2) as valor_comodato
  from public.estoque_itens i
  join public.estoque_categorias c on c.id = i.categoria_id
  left join public.negocios n on n.id = i.negocio_id;
