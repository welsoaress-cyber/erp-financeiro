-- =============================================================================
-- 0088 · Correção — atualizar_lancamento aceita p_parcela_inicial
-- =============================================================================
-- A etapa 45 (0071) deu p_parcela_inicial a criar_lancamento, mas esqueceu de
-- atualizar_lancamento. Como o app monta os parâmetros das duas num lugar só,
-- QUALQUER edição de lançamento passou a falhar com
--   "Could not find the function public.atualizar_lancamento(... p_parcela_inicial ...)".
--
-- Aqui a assinatura passa a bater. A parcela inicial só é aplicada quando o
-- lançamento VIRA recorrente nesta edição (era avulso): em cadeia que já existe,
-- mexer na numeração é trabalho do trigger barrar — e ele barra.
-- =============================================================================

-- as duas assinaturas: a antiga (17) e a nova (18), para poder reaplicar sem erro
drop function if exists public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid, boolean, text, integer, date);
drop function if exists public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid, boolean, text, integer, date, integer);

create function public.atualizar_lancamento(
  p_id uuid, p_descricao text, p_valor numeric, p_data_competencia date,
  p_data_vencimento date default null, p_data_efetivacao date default null,
  p_conta_id uuid default null, p_conta_destino_id uuid default null,
  p_categoria_id uuid default null, p_observacao text default null,
  p_negocio_id uuid default null, p_pessoa_id uuid default null, p_contrato_id uuid default null,
  p_recorrente boolean default false, p_periodicidade text default null,
  p_numero_parcelas integer default null, p_data_fim_recorrencia date default null,
  p_parcela_inicial integer default 1
)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  v_rec boolean := coalesce(p_recorrente, false);
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  perform set_config('erp.motor', 'on', true);
  update public.lancamentos set
    descricao        = btrim(p_descricao),
    valor            = p_valor,
    data_competencia = p_data_competencia,
    data_vencimento  = coalesce(p_data_vencimento, p_data_competencia),
    data_efetivacao  = p_data_efetivacao,
    status           = (case when p_data_efetivacao is null then 'previsto' else 'efetivado' end)::public.status_lancamento,
    conta_id         = coalesce(p_conta_id, conta_id),
    conta_destino_id = case when tipo = 'transferencia' then coalesce(p_conta_destino_id, conta_destino_id) else null end,
    categoria_id     = case when tipo = 'transferencia' then null else coalesce(p_categoria_id, categoria_id) end,
    observacao       = nullif(btrim(coalesce(p_observacao, '')), ''),
    negocio_id       = p_negocio_id,
    pessoa_id        = p_pessoa_id,
    contrato_id      = p_contrato_id,
    recorrente           = v_rec,
    periodicidade        = case when v_rec then p_periodicidade::public.periodicidade_recorrencia end,
    numero_parcelas      = case when v_rec then p_numero_parcelas end,
    -- já era recorrente ⇒ numeração intocada; virou recorrente agora ⇒ começa na parcela pedida
    parcela_atual        = case when v_rec then
                             (case when l.recorrente then coalesce(l.parcela_atual, 1)
                                   else greatest(1, coalesce(p_parcela_inicial, 1)) end)
                           end,
    data_fim_recorrencia = case when v_rec then p_data_fim_recorrencia end
  where id = p_id
  returning * into l;
  perform public.gerar_movimentos(l.id);
  perform public.gerar_proxima_parcela(l.id);
  return l;
end;
$$;

revoke all on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid, boolean, text, integer, date, integer) from public, anon;
grant execute on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid, boolean, text, integer, date, integer) to authenticated;
