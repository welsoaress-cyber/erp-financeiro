-- =============================================================================
-- Migration 0021: motivo de pendência sem consumir tentativa
-- A Edge Function registra "instância offline" no aviso (campo erro) mantendo-o
-- pendente e sem contar tentativa, para o histórico mostrar por que não saiu.
-- =============================================================================
drop function if exists public.registrar_resultado_notificacao(uuid, boolean, text, jsonb);
create or replace function public.registrar_resultado_notificacao(p_id uuid, p_ok boolean, p_erro text default null, p_resposta jsonb default null, p_contar boolean default true)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('erp.motor', 'on', true);
  if p_ok then
    update public.notificacoes_log set status = 'enviado', data_envio = now(), erro = null, resposta_provedor = p_resposta, tentativas = tentativas + 1 where id = p_id and status = 'pendente';
  elsif not p_contar then
    update public.notificacoes_log set erro = left(p_erro, 500) where id = p_id and status = 'pendente';
  else
    update public.notificacoes_log
       set tentativas = tentativas + 1, erro = left(p_erro, 500), resposta_provedor = p_resposta,
           status = case when tentativas + 1 >= 5 then 'erro'::public.status_notificacao else status end
     where id = p_id and status = 'pendente';
  end if;
end;
$$;
revoke all on function public.registrar_resultado_notificacao(uuid, boolean, text, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.registrar_resultado_notificacao(uuid, boolean, text, jsonb, boolean) to service_role;
