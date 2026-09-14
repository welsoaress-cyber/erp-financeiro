-- =============================================================================
-- 0079 · RELATÓRIO POR CENTRO DE CUSTO (Etapa 53)
-- =============================================================================
-- Centro de custo = negócio (etapa 39). Faltava enxergar todos lado a lado:
-- receita, despesa operacional, investimento e resultado do mês por negócio,
-- com detalhe por categoria. View derivada (nada gravado), security_invoker
-- (RLS de lancamentos vale), granularidade categoria × status para o app somar.
-- negocio_id nulo = pessoal. Cancelados não entram; estornos entram negativos.
-- =============================================================================
create view public.vw_centro_custo_mensal
with (security_invoker = true) as
select l.organizacao_id,
       l.negocio_id,
       date_trunc('month', l.data_competencia)::date as mes,
       l.tipo,
       l.status,
       l.categoria_id,
       coalesce(c.nome, '(sem categoria)') as categoria,
       coalesce(c.natureza, 'operacional'::public.natureza_categoria) as natureza,
       sum(l.valor)::numeric(14,2) as valor,
       count(*)::int as lancamentos
  from public.lancamentos l
  left join public.categorias c on c.id = l.categoria_id
 where l.status in ('previsto', 'efetivado') and l.tipo in ('receita', 'despesa')
 group by l.organizacao_id, l.negocio_id, date_trunc('month', l.data_competencia), l.tipo, l.status, l.categoria_id, c.nome, c.natureza;
grant select on public.vw_centro_custo_mensal to authenticated;
