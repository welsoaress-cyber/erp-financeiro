-- =============================================================================
-- 0137 · Projeção de saldo mês a mês (Dashboard)
-- =============================================================================
-- Pedido do proprietário: "quero saber quanto vou ter no final do ano" —
-- saldo acumulado projetado, mês a mês, não só o resultado de um mês isolado.
--
-- Combina duas fontes (nenhuma nova — já existiam separadas):
--   - lancamentos 'previsto' já gerados (parcelas futuras, contratos já
--     faturados adiantado, avulsos) — atrasados de meses anteriores ao atual
--     entram dobrados no mês atual (dívida/crédito que ainda não virou saldo
--     real, mas também não pode desaparecer da projeção);
--   - projecao_contratos (0031): meses futuros dos contratos ativos ainda não
--     faturados, a valor atual, nada gravado.
-- Devolve por negócio (não soma tudo) para o app aplicar o mesmo filtro de
-- negócio/pessoal já usado no resto do Dashboard. O app soma a partir do
-- saldo atual das contas — aqui só entra o fluxo (receita − despesa) de cada mês.
-- =============================================================================

create or replace function public.projecao_saldo_mensal(p_organizacao uuid, p_ate date)
returns table (negocio_id uuid, mes date, tipo public.tipo_lancamento, valor numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_mes_atual date := date_trunc('month', current_date)::date;
begin
  perform public.exigir_membro(p_organizacao);
  if p_ate is null or p_ate < v_mes_atual then
    raise exception 'Período inválido.' using errcode = 'check_violation';
  end if;
  return query
    select l.negocio_id, greatest(date_trunc('month', l.data_competencia)::date, v_mes_atual) as mes, l.tipo, sum(l.valor)
      from public.lancamentos l
     where l.organizacao_id = p_organizacao and l.status = 'previsto' and l.tipo in ('receita', 'despesa')
       and date_trunc('month', l.data_competencia)::date <= p_ate
     group by l.negocio_id, greatest(date_trunc('month', l.data_competencia)::date, v_mes_atual), l.tipo
    union all
    select pc.negocio_id, date_trunc('month', pc.data_competencia)::date as mes, pc.tipo, sum(pc.valor)
      from public.projecao_contratos(p_organizacao, v_mes_atual, p_ate) pc
     group by pc.negocio_id, date_trunc('month', pc.data_competencia)::date, pc.tipo;
end;
$$;
comment on function public.projecao_saldo_mensal(uuid, date) is
  'Fluxo previsto (receita/despesa) por negócio e mês, de agora até p_ate: lançamentos previsto já gerados (atrasados somados no mês atual) + projeção dos contratos (0031) para os meses ainda não faturados. Base para o gráfico de saldo projetado do Dashboard.';

revoke all on function public.projecao_saldo_mensal(uuid, date) from public, anon;
grant execute on function public.projecao_saldo_mensal(uuid, date) to authenticated;
