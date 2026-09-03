-- =============================================================================
-- Migration 0022: ENVIO UMA VEZ POR DIA
-- Decisão do proprietário: um único disparo diário. Geração às 12:00 UTC
-- (09:00 Brasília, migration 0017) e envio às 12:05 UTC. O botão
-- "Enviar pendentes agora" cobre reenvios manuais (ex.: instância estava offline).
-- =============================================================================
do $$
begin
  perform cron.unschedule('erp-notificacoes-envio');
exception when others then null;
end $$;
select cron.schedule(
  'erp-notificacoes-envio',
  '5 12 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificacoes-enviar',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'notificacoes_cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  )
  $$
);
