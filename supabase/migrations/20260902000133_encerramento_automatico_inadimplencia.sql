-- =============================================================================
-- 0133 · Encerramento automático de contrato por inadimplência prolongada
-- =============================================================================
-- Pedido do proprietário: depois de N dias de atraso (régua do negócio já
-- avisou nos pontos configurados em regua_apos), o contrato suspenso deve se
-- encerrar sozinho — e ficar visível em algum lugar pra mandar mensagem de
-- vez em quando pro ex-cliente. Opt-in por negócio (mesmo padrão do bloqueio
-- automático da 0097): só liga quem quiser, cada um com seu prazo.
--
-- Mesma trilha do bloqueio assistido × automático: o fluxo manual continua
-- existindo (abrir o contrato e encerrar pela tela), isso só automatiza pra
-- quem concorda em encerrar sozinho depois de X dias sem pagar.
-- =============================================================================

alter table public.notificacoes_config add column encerramento_automatico boolean not null default false;
comment on column public.notificacoes_config.encerramento_automatico is 'Se true, o robô diário encerra sozinho contratos suspensos há mais de encerramento_apos_dias sem pagar — opt-in, desligado por padrão.';
alter table public.notificacoes_config add column encerramento_apos_dias smallint not null default 30 check (encerramento_apos_dias between 1 and 180);
comment on column public.notificacoes_config.encerramento_apos_dias is 'Dias de atraso (desde o vencimento mais antigo em aberto) para o robô encerrar o contrato sozinho, quando encerramento_automatico está ligado.';

alter table public.contratos add column motivo_encerramento text;
comment on column public.contratos.motivo_encerramento is 'Preenchido só quando o encerramento foi automático (robô de inadimplência); null = encerramento manual pela tela. Usado pra filtrar "encerrados por inadimplência" em Contratos.';

-- Espelho de encerrar_contrato (0117), sem exigir_membro — só o robô chama.
-- Cancela as cobranças "previsto" vencidas como perda (contrato não vai mais cobrar).
create function public.encerrar_contrato_interno(p_contrato_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r record;
begin
  perform set_config('erp.motor', 'on', true);
  update public.contratos set status = 'encerrado', data_fim = current_date, motivo_encerramento = p_motivo where id = p_contrato_id;
  for r in select id, data_vencimento from public.lancamentos where contrato_id = p_contrato_id and status = 'previsto'
  loop
    update public.lancamentos
       set status = 'cancelado', cancelado_em = now(),
           motivo_cancelamento = 'Perda — contrato encerrado automaticamente por inadimplência.',
           data_efetivacao = null
     where id = r.id;
    perform public.gerar_movimentos(r.id);
  end loop;
end;
$$;
revoke all on function public.encerrar_contrato_interno(uuid, text) from public, anon, authenticated;

-- Robô diário: só mexe nos negócios com encerramento_automatico ligado (opt-in),
-- independente do bloqueio_automatico (negócio pode ter um ligado e outro não).
create function public.executar_encerramentos_automaticos()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_neg record; v_ct record; v_total int := 0;
begin
  for v_neg in select negocio_id, encerramento_apos_dias from public.notificacoes_config where encerramento_automatico loop
    for v_ct in
      select c.id, min(l.data_vencimento) as vencida_desde
        from public.contratos c
        join public.lancamentos l on l.contrato_id = c.id and l.tipo = 'receita' and l.status = 'previsto'
       where c.negocio_id = v_neg.negocio_id and c.status = 'suspenso' and c.tipo_financeiro = 'receita'
       group by c.id
      having min(l.data_vencimento) <= current_date - v_neg.encerramento_apos_dias
    loop
      perform public.encerrar_contrato_interno(v_ct.id,
        'Encerrado automaticamente — ' || v_neg.encerramento_apos_dias || ' dia(s) sem pagar (vencido desde ' || to_char(v_ct.vencida_desde, 'DD/MM/YYYY') || ').');
      v_total := v_total + 1;
    end loop;
  end loop;
  return jsonb_build_object('encerrados', v_total);
end;
$$;
revoke all on function public.executar_encerramentos_automaticos() from public, anon, authenticated;
grant execute on function public.executar_encerramentos_automaticos() to service_role;

-- Mesmo robô diário do bloqueio (0097/0098/0114) também cuida do encerramento —
-- um único agendamento, sem cron novo. Preserva a sincronização do curso
-- cortesia (0114) que já rodava aqui.
create or replace function public.executar_bloqueios_automaticos()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_neg record; v_item record; v_total int := 0; v_curso jsonb; v_enc jsonb;
begin
  for v_neg in select negocio_id from public.notificacoes_config where bloqueio_automatico loop
    perform public.gerar_bloqueios_interno(v_neg.negocio_id);
    for v_item in select id from public.bloqueios where negocio_id = v_neg.negocio_id and status = 'pendente' loop
      perform public.executar_bloqueio_interno(v_item.id);
      v_total := v_total + 1;
    end loop;
  end loop;
  v_curso := public.sincronizar_cortesia_curso_automatico();
  v_enc := public.executar_encerramentos_automaticos();
  return jsonb_build_object('executados', v_total, 'curso_suspensos', v_curso->'suspensos', 'curso_liberados', v_curso->'liberados', 'encerrados', v_enc->'encerrados');
end;
$$;

-- Relatório: contratos encerrados automaticamente por inadimplência.
create view public.vw_rel_encerramentos_inadimplencia with (security_invoker = true) as
select c.id, c.organizacao_id, c.negocio_id, n.nome as negocio, p.nome as cliente, p.telefone,
       c.codigo, c.data_fim, c.motivo_encerramento
  from public.contratos c
  join public.negocios n on n.id = c.negocio_id
  join public.pessoas p on p.id = c.pessoa_id
 where c.status = 'encerrado' and c.motivo_encerramento is not null;
grant select on public.vw_rel_encerramentos_inadimplencia to authenticated;
