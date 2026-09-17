-- Agendamento diário do bloqueio automático (0097). pg_cron, extensão gratuita
-- do Supabase. Se o projeto estiver pausado (plano Free, 7 dias sem uso), o
-- agendamento não roda — o "Bloqueei na rede" manual em Cobrança continua
-- funcionando normalmente enquanto isso.
create extension if not exists pg_cron;
grant usage on schema cron to postgres;

do $$
begin
  perform cron.unschedule('erp-bloqueios-automaticos');
exception when others then null;
end $$;

select cron.schedule('erp-bloqueios-automaticos', '0 7 * * *', $$select public.executar_bloqueios_automaticos()$$); -- 07:00 UTC = 04:00 Brasília, depois do faturamento (06:00 UTC)
