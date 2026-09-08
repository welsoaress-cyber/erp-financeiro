-- =============================================================================
-- 0040 · Encargos (juros/multa) ao pagar com atraso
-- =============================================================================
-- Ao dar baixa em um lançamento vencido, o proprietário pode informar os
-- encargos cobrados: o valor deles é somado SÓ nesta parcela (as futuras não
-- mudam) e registrado na observação. Zero ou omitido = comportamento antigo.
-- =============================================================================

drop function public.efetivar_lancamento(uuid, date);

create function public.efetivar_lancamento(p_id uuid, p_data_efetivacao date default current_date, p_encargos numeric default 0)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  n public.lancamentos%rowtype;
  v_valor_original numeric;
  v_obs_original text;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.status <> 'previsto' then
    raise exception 'Somente lançamentos previstos podem ser efetivados.' using errcode = 'check_violation';
  end if;
  if p_encargos is null or p_encargos < 0 then
    raise exception 'Encargos não podem ser negativos.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  v_valor_original := l.valor;
  v_obs_original := l.observacao;
  if p_encargos > 0 then
    update public.lancamentos
       set valor = valor + round(p_encargos, 2),
           observacao = trim(both e'\n' from coalesce(observacao, '') || e'\n' ||
             'Encargos por atraso: R$ ' || replace(to_char(round(p_encargos, 2), 'FM999999990.00'), '.', ','))
     where id = p_id;
  end if;
  update public.lancamentos set status = 'efetivado', data_efetivacao = p_data_efetivacao where id = p_id returning * into l;
  perform public.gerar_movimentos(l.id);
  n := public.gerar_proxima_parcela(l.id);
  -- os encargos são só desta parcela: a próxima (quando gerada aqui) volta ao valor normal
  if p_encargos > 0 and n.id is not null then
    update public.lancamentos set valor = v_valor_original, observacao = v_obs_original where id = n.id;
  end if;
  if p_data_efetivacao > l.data_vencimento then
    if l.recorrente then
      perform public.reancorar_recorrencia(l.id, p_data_efetivacao);
    elsif l.contrato_id is not null and l.origem = 'faturamento' then
      update public.contratos
         set dia_vencimento = least(extract(day from p_data_efetivacao)::int, 31)::smallint
       where id = l.contrato_id and status = 'ativo';
    end if;
  end if;
  return l;
end;
$$;
revoke all on function public.efetivar_lancamento(uuid, date, numeric) from public, anon;
grant execute on function public.efetivar_lancamento(uuid, date, numeric) to authenticated;
