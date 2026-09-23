-- Etapa 57 (ajuste): botão "Atualizar bloqueio/desbloqueio agora" na Cobrança, para
-- negócios com bloqueio_automatico ligado. O robô diário (0097/0098) só roda às 00:00;
-- quem está lançando contratos ao longo do dia não quer esperar virar o dia para o
-- status do contrato (e da API de consulta) refletir o pagamento/vencimento.
-- Reaproveita gerar_bloqueios_interno/executar_bloqueio_interno (0097) — mesma lógica do
-- robô, mas por negócio e sob exigir_membro, em vez de rodar para todos via pg_cron.
create function public.executar_bloqueios_agora(p_negocio_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; v_automatico boolean; v_item record; v_total int := 0;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(n.organizacao_id);
  select bloqueio_automatico into v_automatico from public.notificacoes_config where negocio_id = p_negocio_id;
  if not coalesce(v_automatico, false) then
    raise exception 'Bloqueio automático não está ligado para este negócio.' using errcode = 'check_violation';
  end if;
  perform public.gerar_bloqueios_interno(p_negocio_id);
  for v_item in select id from public.bloqueios where negocio_id = p_negocio_id and status = 'pendente' loop
    perform public.executar_bloqueio_interno(v_item.id);
    v_total := v_total + 1;
  end loop;
  return jsonb_build_object('executados', v_total);
end;
$$;
revoke all on function public.executar_bloqueios_agora(uuid) from public, anon;
grant execute on function public.executar_bloqueios_agora(uuid) to authenticated;
