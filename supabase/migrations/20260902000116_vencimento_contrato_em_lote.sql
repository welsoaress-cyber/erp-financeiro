-- =============================================================================
-- 0116 · Alterar vencimento de cobrança de contrato em lote (sem reabrir contrato)
-- =============================================================================
-- Até aqui, mudar o vencimento de uma fatura gerada por contrato só dava pra
-- fazer uma de cada vez (editar o lançamento) ou mexendo em contratos.dia_vencimento
-- (vale só pro que ainda não foi gerado). Decisão do proprietário: a alteração
-- de vencimento de uma cobrança de contrato tem que poder valer pras
-- próximas também, direto do lançamento — sem precisar encerrar o contrato e
-- abrir outro. Vale para qualquer negócio (servidor, provedor, internet,
-- qualquer tipo), não só pré-pago.
--
-- cascatear_vencimento_contrato(p_id, p_escopo): depois de editar o
-- vencimento DESTE lançamento pelo caminho normal (atualizar_lancamento), o
-- app chama esta função pra propagar:
--   'futuras' — as próximas faturas do mesmo contrato que já tinham sido
--               geradas (ainda previstas) acompanham o novo dia; o contrato
--               também é atualizado, pro que o faturamento ainda vai gerar.
--   'todas'   — igual a 'futuras', e também as faturas já efetivadas (pagas)
--               do mesmo contrato têm a data de vencimento corrigida (é só
--               registro — não mexe em saldo, movimento nem nos pontos de
--               pontualidade, que usam data_vencimento_original e nunca mudam).
-- =============================================================================

create function public.cascatear_vencimento_contrato(p_id uuid, p_escopo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  v_dia smallint;
begin
  if p_escopo not in ('futuras', 'todas') then
    raise exception 'Escopo inválido.' using errcode = 'check_violation';
  end if;
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.contrato_id is null or l.origem <> 'faturamento' then
    raise exception 'Só vale para cobrança gerada por contrato.' using errcode = 'check_violation';
  end if;

  v_dia := least(extract(day from l.data_vencimento)::int, 31)::smallint;
  perform set_config('erp.motor', 'on', true);

  update public.contratos set dia_vencimento = v_dia where id = l.contrato_id and status = 'ativo';

  update public.lancamentos
     set data_vencimento = public.data_vencimento_no_mes(data_competencia, v_dia)
   where contrato_id = l.contrato_id and status = 'previsto' and data_competencia > l.data_competencia;

  if p_escopo = 'todas' then
    update public.lancamentos
       set data_vencimento = public.data_vencimento_no_mes(data_competencia, v_dia)
     where contrato_id = l.contrato_id and status = 'efetivado';
  end if;
end;
$$;
revoke all on function public.cascatear_vencimento_contrato(uuid, text) from public, anon;
grant execute on function public.cascatear_vencimento_contrato(uuid, text) to authenticated;
