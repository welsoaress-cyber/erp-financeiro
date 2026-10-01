-- =============================================================================
-- 0117 · Encerrar contrato pode cancelar as cobranças em aberto
-- =============================================================================
-- Contrato encerrado continuava com lançamentos "previsto" aparecendo em Contas
-- a Receber/Pagar pra sempre — o faturamento automático já não gera mais nada
-- pra ele (exige status = 'ativo'), mas o que já tinha sido gerado antes do
-- encerramento ficava órfão na lista. Decisão do proprietário:
--   - Suspenso não mexe em nada: é bloqueio por inadimplência, cancelar a
--     cobrança apagaria a dívida que motivou o bloqueio.
--   - Encerrar contrato passa a perguntar (opt-in, via p_cancelar_pendencias)
--     se cancela as cobranças "previsto" do contrato. As que ainda não tinham
--     vencido na data do encerramento são canceladas normalmente; as que já
--     estavam vencidas entram como perda (motivo_cancelamento distinto, pra
--     não se confundir com uma cobrança que nunca existiu).
-- =============================================================================

create function public.encerrar_contrato(p_id uuid, p_data_fim date, p_cancelar_pendencias boolean default false)
returns public.contratos
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.contratos%rowtype;
  r record;
  v_motivo text;
begin
  select * into c from public.contratos where id = p_id;
  if not found then raise exception 'Contrato não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(c.organizacao_id);
  if c.status = 'encerrado' then
    raise exception 'Contrato já encerrado.' using errcode = 'check_violation';
  end if;
  if p_data_fim < c.data_inicio then
    raise exception 'A data de encerramento não pode ser anterior ao início do contrato.' using errcode = 'check_violation';
  end if;

  update public.contratos set status = 'encerrado', data_fim = p_data_fim where id = p_id returning * into c;

  if p_cancelar_pendencias then
    for r in select id, data_vencimento from public.lancamentos where contrato_id = p_id and status = 'previsto'
    loop
      v_motivo := case when r.data_vencimento < p_data_fim
        then 'Perda — contrato encerrado em ' || to_char(p_data_fim, 'DD/MM/YYYY') || ' com cobrança já vencida.'
        else 'Contrato encerrado em ' || to_char(p_data_fim, 'DD/MM/YYYY') || '.' end;
      perform public.cancelar_lancamento(r.id, v_motivo);
    end loop;
  end if;

  return c;
end;
$$;
revoke all on function public.encerrar_contrato(uuid, date, boolean) from public, anon;
grant execute on function public.encerrar_contrato(uuid, date, boolean) to authenticated;
