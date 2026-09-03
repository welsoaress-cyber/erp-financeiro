-- =============================================================================
-- Migration 0020: DISPARO MANUAL DO ENVIO + JOB A CADA 5 MINUTOS
-- disparar_envio_notificacoes(): RPC para a interface; faz o mesmo que o job
-- (net.http_post para a Edge Function com os segredos do Vault), sem expor
-- segredo ao navegador. Só membros da organização. Assíncrono: a resposta
-- chega em net._http_response; a tela reconsulta o histórico.
-- =============================================================================
create or replace function public.disparar_envio_notificacoes()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare v_url text; v_secret text; v_req bigint;
begin
  if not exists (select public.minhas_organizacoes()) then
    raise exception 'Sem organização.' using errcode = 'insufficient_privilege';
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'notificacoes_cron_secret';
  if v_url is null or v_secret is null then
    raise exception 'Envio real não configurado (segredos project_url / notificacoes_cron_secret ausentes no Vault).' using errcode = 'check_violation';
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/notificacoes-enviar',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  ) into v_req;
  return v_req;
end;
$$;
revoke all on function public.disparar_envio_notificacoes() from public, anon;
grant execute on function public.disparar_envio_notificacoes() to authenticated;

-- job a cada 5 minutos no horário comercial
do $$
begin
  perform cron.unschedule('erp-notificacoes-envio');
exception when others then null;
end $$;
select cron.schedule(
  'erp-notificacoes-envio',
  '*/5 11-21 * * *',
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
