-- =============================================================================
-- 0146 · Reconciliação Asaas passa de 5 em 5 para 30 em 30 minutos
-- =============================================================================
-- Pedido do proprietário: 5 em 5 minutos gera log/histórico demais no banco
-- sem necessidade (confirmação de boleto não precisa ser em tempo real como
-- o Pix). Mesma lógica, só o intervalo muda.
-- =============================================================================

select cron.unschedule('erp-asaas-reconciliar');
select cron.schedule('erp-asaas-reconciliar', '*/30 * * * *', $$select public.asaas_reconciliar_agendado()$$);
