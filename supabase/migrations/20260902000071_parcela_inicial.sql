-- =============================================================================
-- 0071 · Etapa 45 — Parcelamento iniciando de uma parcela específica
-- =============================================================================
-- Quem migra uma dívida em andamento (ex.: 24x, já pagou a 1ª fora do
-- sistema) lança "24 parcelas, iniciar na 2": nascem 23 lançamentos numerados
-- 2/24 … 24/24 — a numeração reflete o CONTRATO, não a quantidade gerada.
-- criar_lancamento ganha p_parcela_inicial (default 1, comportamento igual ao
-- de sempre) e o trigger passa a aceitar raiz de cadeia com parcela > 1.
-- =============================================================================

drop function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid, boolean, text, integer, date);

CREATE OR REPLACE FUNCTION public.criar_lancamento(p_tipo text, p_descricao text, p_valor numeric, p_data_competencia date, p_data_vencimento date DEFAULT NULL::date, p_data_efetivacao date DEFAULT NULL::date, p_conta_id uuid DEFAULT NULL::uuid, p_conta_destino_id uuid DEFAULT NULL::uuid, p_categoria_id uuid DEFAULT NULL::uuid, p_observacao text DEFAULT NULL::text, p_negocio_id uuid DEFAULT NULL::uuid, p_pessoa_id uuid DEFAULT NULL::uuid, p_contrato_id uuid DEFAULT NULL::uuid, p_recorrente boolean DEFAULT false, p_periodicidade text DEFAULT NULL::text, p_numero_parcelas integer DEFAULT NULL::integer, p_data_fim_recorrencia date DEFAULT NULL::date, p_parcela_inicial integer DEFAULT 1)
 RETURNS lancamentos
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org uuid;
  l public.lancamentos%rowtype;
begin
  select organizacao_id into v_org from public.contas where id = p_conta_id;
  perform public.exigir_membro(v_org);
  perform set_config('erp.motor', 'on', true);
  insert into public.lancamentos (
    organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao,
    status, conta_id, conta_destino_id, categoria_id, observacao, negocio_id, pessoa_id, contrato_id,
    recorrente, periodicidade, numero_parcelas, parcela_atual, data_fim_recorrencia
  ) values (
    v_org, p_tipo::public.tipo_lancamento, btrim(p_descricao), p_valor, p_data_competencia,
    coalesce(p_data_vencimento, p_data_competencia), p_data_efetivacao,
    (case when p_data_efetivacao is null then 'previsto' else 'efetivado' end)::public.status_lancamento,
    p_conta_id, p_conta_destino_id, p_categoria_id, nullif(btrim(coalesce(p_observacao, '')), ''), p_negocio_id, p_pessoa_id, p_contrato_id,
    coalesce(p_recorrente, false),
    case when coalesce(p_recorrente, false) then p_periodicidade::public.periodicidade_recorrencia end,
    case when coalesce(p_recorrente, false) then p_numero_parcelas end,
    case when coalesce(p_recorrente, false) then greatest(1, coalesce(p_parcela_inicial, 1)) end,
    case when coalesce(p_recorrente, false) then p_data_fim_recorrencia end
  ) returning * into l;
  perform public.gerar_movimentos(l.id);
  perform public.gerar_proxima_parcela(l.id); -- criado já efetivado ⇒ próxima parcela na hora
  return l;
end;
$function$;

CREATE OR REPLACE FUNCTION public.tg_lancamentos_recorrencia()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_tem_filha boolean;
  o public.lancamentos%rowtype;
begin
  -- tipo derivado: fixa (sem parcelas) ou parcelada
  new.tipo_recorrencia := case when new.recorrente then (case when new.numero_parcelas is null then 'fixa' else 'parcelada' end)::public.tipo_recorrencia end;
  if new.recorrente then
    if new.origem = 'faturamento' then
      raise exception 'Cobrança gerada por contrato não pode ser recorrente: o faturamento já é automático.' using errcode = 'check_violation';
    end if;
    if new.data_fim_recorrencia is not null and new.data_fim_recorrencia < new.data_vencimento then
      raise exception 'A data de término da recorrência deve ser igual ou posterior ao vencimento.' using errcode = 'check_violation';
    end if;
  end if;

  if tg_op = 'INSERT' then
    if new.lancamento_origem_id is not null then
      select * into o from public.lancamentos where id = new.lancamento_origem_id;
      if not found or o.organizacao_id <> new.organizacao_id or not o.recorrente then
        raise exception 'Lançamento de origem inválido.' using errcode = 'check_violation';
      end if;
      if new.parcela_atual <> o.parcela_atual + 1 then
        raise exception 'Parcela fora de sequência.' using errcode = 'check_violation';
      end if;
    elsif new.recorrente and (new.parcela_atual < 1 or (new.numero_parcelas is not null and new.parcela_atual > new.numero_parcelas)) then
      raise exception 'Parcela inicial inválida (use de 1 até o total de parcelas).' using errcode = 'check_violation';
    end if;
    return new;
  end if;

  -- UPDATE
  if new.lancamento_origem_id is distinct from old.lancamento_origem_id then
    raise exception 'A origem da parcela não pode ser alterada.' using errcode = 'check_violation';
  end if;
  v_tem_filha := exists (select 1 from public.lancamentos f where f.lancamento_origem_id = old.id);
  if old.recorrente and (v_tem_filha or old.parcela_atual > 1) then
    if new.recorrente is distinct from old.recorrente or new.periodicidade is distinct from old.periodicidade
       or new.numero_parcelas is distinct from old.numero_parcelas or new.data_fim_recorrencia is distinct from old.data_fim_recorrencia
       or new.parcela_atual is distinct from old.parcela_atual then
      raise exception 'A recorrência não pode ser alterada: já existem parcelas geradas.' using errcode = 'check_violation';
    end if;
  end if;
  if old.recorrente and v_tem_filha then
    if (new.conta_id <> old.conta_id and coalesce(current_setting('erp.trocar_conta', true), '') <> 'on')
       or new.conta_destino_id is distinct from old.conta_destino_id
       or new.categoria_id is distinct from old.categoria_id or new.negocio_id is distinct from old.negocio_id
       or new.pessoa_id is distinct from old.pessoa_id or new.contrato_id is distinct from old.contrato_id then
      raise exception 'Lançamento com parcelas geradas: só descrição, valor, observação e data podem ser alterados.' using errcode = 'check_violation';
    end if;
    if (new.data_competencia <> old.data_competencia or new.data_vencimento <> old.data_vencimento)
       and coalesce(current_setting('erp.editar_data', true), '') <> 'on' then
      raise exception 'Data de recorrência muda pela edição em lote ("apenas esta" ou "esta e as futuras").' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid, boolean, text, integer, date, integer) from public, anon;
grant execute on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid, boolean, text, integer, date, integer) to authenticated;
