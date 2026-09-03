-- =============================================================================
-- 0028 · Saldo inicial do mês (Resumo Financeiro do Período, no Dashboard)
-- =============================================================================
-- Etapa 15. O resto do resumo (previsto × realizado de receitas/despesas, resultado,
-- total consolidado, por negócio) é calculado no app a partir dos lançamentos do mês,
-- que já são buscados pelo Financeiro. Só o saldo inicial (o que já existia antes do
-- mês começar) precisa de uma consulta própria, para não trazer o histórico de
-- movimentos inteiro para o navegador.
create or replace function public.saldo_inicial_mes(p_mes date)
returns table (negocio_id uuid, saldo numeric)
language sql
stable
set search_path = public
as $$
  select s.negocio_id, sum(s.saldo)::numeric(14,2)
    from (
      select c.id, c.negocio_id,
             c.saldo_inicial + coalesce((select sum(m.valor) from public.movimentos m where m.conta_id = c.id and m.data < date_trunc('month', p_mes)::date), 0) as saldo
        from public.contas c
       where c.organizacao_id in (select public.minhas_organizacoes()) and c.ativo and c.data_inicio < date_trunc('month', p_mes)::date
    ) s
   group by s.negocio_id;
$$;
revoke all on function public.saldo_inicial_mes(date) from public, anon;
grant execute on function public.saldo_inicial_mes(date) to authenticated;
