-- =============================================================================
-- 0119 · "Atualizar bloqueio/desbloqueio agora" também sincroniza o curso cortesia
-- =============================================================================
-- A 0114 ligou a sincronização do curso cortesia (sincronizar_cortesia_curso_logica)
-- só em executar_bloqueios_automaticos — o robô diário (pg_cron 00:00). O botão
-- manual "Atualizar bloqueio/desbloqueio agora" chama executar_bloqueios_agora,
-- uma função POR NEGÓCIO separada, que nunca chamava essa sincronização: um
-- contrato de receita podia ser suspenso na hora pelo botão, mas o curso
-- cortesia da mesma pessoa só acompanhava na virada do dia — a Leveduca via
-- "Ativo" até lá. Chama a mesma sincronização aqui também.
-- =============================================================================

create or replace function public.executar_bloqueios_agora(p_negocio_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; v_automatico boolean; v_item record; v_total int := 0; v_curso jsonb;
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
  v_curso := public.sincronizar_cortesia_curso_logica(n.organizacao_id);
  return jsonb_build_object('executados', v_total, 'curso_suspensos', v_curso->'suspensos', 'curso_liberados', v_curso->'liberados');
end;
$$;
