-- =============================================================================
-- Migration 0039: FECHAMENTO DIÁRIO DAS FATURAS DE CARTÃO (pg_cron)
-- Roda todo dia 05:30 UTC (02:30 Brasília): fecha faturas no dia de fechamento
-- de cada cartão (idempotente) e marca as vencidas.
-- =============================================================================
do $$
begin
  perform cron.unschedule('erp-cartoes-diario');
exception when others then null;
end $$;
select cron.schedule('erp-cartoes-diario', '30 5 * * *', $$select public.fechar_faturas_cartoes()$$);
