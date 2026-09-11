-- =============================================================================
-- 0060 · Etapa 32 — BI gerencial (views consolidadas, sem tabelas novas)
-- =============================================================================
-- Uma linha por negócio × mês (últimos 13 meses + mês corrente), calculada em
-- tempo real a partir de contratos e lançamentos:
-- - novos contratos, cancelamentos e ativos no fim do mês
-- - churn % = cancelamentos ÷ ativos no início do mês
-- - MRR no fim do mês (valor mensalizado dos contratos de receita vigentes)
-- - ticket médio = MRR ÷ ativos
-- - receita prevista com vencimento no mês, recebida (efetivada) e
--   inadimplência % = vencidas em aberto ÷ previstas vencidas no mês
-- Desempenho por técnico e payback continuam nas views das etapas 29/28B;
-- a tela Gerencial junta tudo e exporta CSV.
-- =============================================================================

create view public.vw_bi_mensal_negocio
with (security_invoker = true) as
with meses as (
  select date_trunc('month', d)::date as mes
    from generate_series(date_trunc('month', current_date) - interval '12 months', date_trunc('month', current_date), interval '1 month') d
), base as (
  select n.organizacao_id, n.id as negocio_id, n.nome as negocio, m.mes
    from public.negocios n cross join meses m
), contratos_m as (
  select b.organizacao_id, b.negocio_id, b.negocio, b.mes,
         count(c.id) filter (where date_trunc('month', c.data_inicio) = b.mes) as novos,
         count(c.id) filter (where c.data_fim is not null and date_trunc('month', c.data_fim) = b.mes) as cancelamentos,
         count(c.id) filter (where c.data_inicio < b.mes and (c.data_fim is null or c.data_fim >= b.mes)) as ativos_inicio,
         count(c.id) filter (where c.data_inicio < (b.mes + interval '1 month') and (c.data_fim is null or c.data_fim >= (b.mes + interval '1 month'))) as ativos_fim,
         coalesce(sum(case c.periodicidade when 'mensal' then c.valor when 'bimestral' then c.valor / 2 when 'trimestral' then c.valor / 3
                                           when 'semestral' then c.valor / 6 when 'anual' then c.valor / 12 else 0 end)
                  filter (where c.data_inicio < (b.mes + interval '1 month') and (c.data_fim is null or c.data_fim >= (b.mes + interval '1 month'))), 0) as mrr
    from base b
    left join public.contratos c on c.negocio_id = b.negocio_id and c.tipo_financeiro = 'receita'
   group by 1, 2, 3, 4
), receitas_m as (
  select c.negocio_id, date_trunc('month', l.data_vencimento)::date as mes,
         sum(l.valor) filter (where l.status <> 'cancelado') as previsto,
         sum(l.valor) filter (where l.status = 'efetivado') as recebido,
         sum(l.valor) filter (where l.status = 'previsto' and l.data_vencimento < current_date) as vencido_aberto
    from public.lancamentos l
    join public.contratos c on c.id = l.contrato_id
   where l.tipo = 'receita'
   group by 1, 2
)
select cm.organizacao_id, cm.negocio_id, cm.negocio, to_char(cm.mes, 'YYYY-MM') as mes,
       cm.novos, cm.cancelamentos, cm.ativos_inicio, cm.ativos_fim,
       case when cm.ativos_inicio > 0 then round(cm.cancelamentos * 100.0 / cm.ativos_inicio, 1) else 0 end as churn_pct,
       round(cm.mrr, 2)::numeric(14,2) as mrr,
       case when cm.ativos_fim > 0 then round(cm.mrr / cm.ativos_fim, 2) else 0 end::numeric(14,2) as ticket_medio,
       coalesce(round(r.previsto, 2), 0)::numeric(14,2) as previsto,
       coalesce(round(r.recebido, 2), 0)::numeric(14,2) as recebido,
       coalesce(round(r.vencido_aberto, 2), 0)::numeric(14,2) as vencido_aberto,
       case when coalesce(r.previsto, 0) > 0 then round(coalesce(r.vencido_aberto, 0) * 100.0 / r.previsto, 1) else 0 end as inadimplencia_pct
  from contratos_m cm
  left join receitas_m r on r.negocio_id = cm.negocio_id and r.mes = cm.mes;

revoke all on public.vw_bi_mensal_negocio from public, anon;
grant select on public.vw_bi_mensal_negocio to authenticated;
