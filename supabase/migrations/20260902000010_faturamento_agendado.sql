-- =============================================================================
-- Migration 0010: AGENDAMENTO DIÁRIO DO FATURAMENTO (pg_cron)
-- Extensão gratuita do Supabase. Se o projeto estiver pausado (plano Free,
-- 7 dias sem uso), o agendamento não roda; o botão "Gerar agora" cobre o atraso.
-- =============================================================================
create extension if not exists pg_cron;
grant usage on schema cron to postgres;

do $$
begin
  perform cron.unschedule('erp-faturamento-diario');
exception when others then null;
end $$;

select cron.schedule('erp-faturamento-diario', '0 6 * * *', $$select public.gerar_faturamento_todas()$$); -- 06:00 UTC = 03:00 Brasília
