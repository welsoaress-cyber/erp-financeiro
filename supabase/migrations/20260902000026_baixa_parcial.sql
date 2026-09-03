-- =============================================================================
-- 0026 · Baixa parcial (Módulo Financeiro: contas a receber / a pagar)
-- =============================================================================
-- Recebe/paga parte de um lançamento previsto: o lançamento original fica efetivado com o valor pago
-- e o restante vira um novo lançamento previsto (mesmos dados, sem recorrência), para nova baixa.
-- Em lançamento recorrente, a próxima parcela é gerada com o valor cheio (antes de reduzir o atual).
create or replace function public.baixar_parcial(p_id uuid, p_valor numeric, p_data_efetivacao date default current_date)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  r public.lancamentos%rowtype;
  v_restante numeric(14,2);
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.status <> 'previsto' then raise exception 'Somente lançamentos previstos aceitam baixa parcial.' using errcode = 'check_violation'; end if;
  if l.tipo = 'transferencia' then raise exception 'Transferência não aceita baixa parcial.' using errcode = 'check_violation'; end if;
  if p_valor is null or p_valor <= 0 or p_valor >= l.valor then
    raise exception 'O valor da baixa parcial deve ser maior que zero e menor que % .', public.moeda_br(l.valor) using errcode = 'check_violation';
  end if;
  v_restante := round(l.valor - p_valor, 2);
  perform set_config('erp.motor', 'on', true);

  -- efetiva com o valor cheio (gera a próxima parcela, se recorrente) e só então reduz para o valor pago
  update public.lancamentos set status = 'efetivado', data_efetivacao = p_data_efetivacao where id = p_id;
  perform public.gerar_proxima_parcela(p_id);
  update public.lancamentos set valor = p_valor where id = p_id returning * into l;
  perform public.gerar_movimentos(l.id);

  insert into public.lancamentos (
    organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
    conta_id, conta_destino_id, categoria_id, observacao, origem, negocio_id, pessoa_id, contrato_id
  ) values (
    l.organizacao_id, l.tipo, l.descricao, v_restante, l.data_competencia, l.data_vencimento, null, 'previsto',
    l.conta_id, null, l.categoria_id,
    left(coalesce(l.observacao || ' ', '') || 'Saldo restante após baixa parcial de ' || public.moeda_br(p_valor) || ' em ' || to_char(p_data_efetivacao, 'DD/MM/YYYY') || '.', 500),
    l.origem, l.negocio_id, l.pessoa_id, l.contrato_id
  ) returning * into r;
  return l;
end;
$$;
revoke all on function public.baixar_parcial(uuid, numeric, date) from public, anon;
grant execute on function public.baixar_parcial(uuid, numeric, date) to authenticated;
