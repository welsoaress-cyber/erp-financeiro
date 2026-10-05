-- =============================================================================
-- 0125 · Dashboard Operacional: Agenda Financeira (A Pagar | A Receber | Saldo
-- Projetado por período) — Hoje, Próximos 7 dias, Próximos 30 dias, Acima de 30.
-- =============================================================================
-- Única peça nova de SQL do redesenho do dashboard: os demais blocos (Resumo,
-- Pendências, Visão por Negócio, Movimentações) já eram cobertos por hooks e
-- views existentes (saldo por conta, vw_resultado_mensal_negocio, contratos
-- suspensos, lançamentos vencidos, pedidos de compra, saúde de notificações).
-- Faltava só a soma de previstos por faixa de vencimento — por isso uma view,
-- agregada no banco, em vez de puxar todos os previstos pro navegador.
--
-- Faixas mutuamente exclusivas (não cumulativas): hoje | 7dias (amanhã..+7) |
-- 30dias (+8..+30) | mais30 (>+30). Vencidos (data_vencimento < hoje) não
-- entram aqui — já têm seu próprio bloco em Pendências.
-- =============================================================================

create or replace view public.vw_dashboard_agenda
with (security_invoker = true) as
select l.organizacao_id, l.negocio_id, l.tipo,
       case
         when l.data_vencimento = current_date then 'hoje'
         when l.data_vencimento <= current_date + 7 then '7dias'
         when l.data_vencimento <= current_date + 30 then '30dias'
         else 'mais30'
       end as bucket,
       l.valor
  from public.lancamentos l
 where l.status = 'previsto'
   and l.tipo in ('receita', 'despesa')
   and l.data_vencimento >= current_date;
