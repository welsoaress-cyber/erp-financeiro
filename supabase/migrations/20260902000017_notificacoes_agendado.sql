-- =============================================================================
-- Migration 0017: AGENDAMENTO DIÁRIO DAS NOTIFICAÇÕES (pg_cron, gratuito)
-- 12:00 UTC = 09:00 Brasília: dentro do horário comercial padrão (08–18).
-- Fora do horário do negócio, os avisos ficam pendentes até a próxima execução.
-- =============================================================================
create extension if not exists pg_cron;
grant usage on schema cron to postgres;

do $$
begin
  perform cron.unschedule('erp-notificacoes-diario');
exception when others then null;
end $$;

select cron.schedule('erp-notificacoes-diario', '0 12 * * *', $$select public.executar_notificacoes_todas()$$);
