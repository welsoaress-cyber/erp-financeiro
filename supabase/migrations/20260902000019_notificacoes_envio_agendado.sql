-- =============================================================================
-- Migration 0019: AGENDAMENTO DA EDGE FUNCTION DE ENVIO (pg_cron + pg_net + Vault)
-- A cada 15 min entre 11:00 e 21:59 UTC (08:00–18:59 Brasília) chama
-- /functions/v1/notificacoes-enviar. Só faz algo se houver pendentes do provedor evolution.
-- PRÉ-REQUISITO (uma vez, no SQL Editor, com os valores reais — nunca no repositório):
--   select vault.create_secret('https://SEU-REF.supabase.co', 'project_url');
--   select vault.create_secret('UM-SEGREDO-LONGO-ALEATORIO', 'notificacoes_cron_secret');
-- O mesmo segredo vai no secret NOTIFICACOES_CRON_SECRET da Edge Function.
-- =============================================================================
create extension if not exists pg_cron;
create extension if not exists pg_net;
grant usage on schema cron to postgres;

do $$
begin
  if not exists (select 1 from vault.decrypted_secrets where name = 'project_url')
     or not exists (select 1 from vault.decrypted_secrets where name = 'notificacoes_cron_secret') then
    raise exception 'Crie os segredos project_url e notificacoes_cron_secret no Vault antes desta migration.';
  end if;
end $$;

do $$
begin
  perform cron.unschedule('erp-notificacoes-envio');
exception when others then null;  -- ainda não existia
end $$;

select cron.schedule(
  'erp-notificacoes-envio',
  '*/15 11-21 * * *',
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
