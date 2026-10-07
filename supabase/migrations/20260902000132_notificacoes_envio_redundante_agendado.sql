-- =============================================================================
-- Migration 0132: redundância no envio de notificações (falha às 9h não trava o dia)
-- =============================================================================
-- A 0022 rodava o envio só 1x/dia (09:05 Brasília) — se a VM da Evolution estivesse
-- lenta/reiniciando naquele minuto exato, o aviso ficava pendente até alguém clicar
-- "Enviar pendentes agora" manualmente. A infra de retry já existia no banco
-- (notificacoes_para_envio já pega pendentes de qualquer hora dentro do horário
-- comercial, sem gastar tentativa quando a instância está offline — 0021); só
-- faltava o robô rodar mais de uma vez. Agora roda de hora em hora, 09:05 a 18:05
-- Brasília (cobre o horário comercial padrão) — pendente de uma hora é pego sozinho
-- na próxima. timeout_milliseconds subiu de 120s pra 150s, folga para o timeout do
-- teste de conexão ter subido de 8s para 20s (correção de falso-negativo, Edge
-- Function) sem estourar o tempo do job.
-- =============================================================================
do $$
begin
  perform cron.unschedule('erp-notificacoes-envio');
exception when others then null;
end $$;
select cron.schedule(
  'erp-notificacoes-envio',
  '5 12-21 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notificacoes-enviar',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'notificacoes_cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 150000
  )
  $$
);
