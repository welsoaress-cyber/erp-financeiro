-- =============================================================================
-- 0041 · Escolher a conta na hora de pagar/receber
-- =============================================================================
-- A baixa pode acontecer por outro banco que não o previsto no lançamento:
-- efetivar_lancamento ganha p_conta_id (opcional) e troca a conta SÓ desta
-- parcela antes de gerar os movimentos. O trigger de recorrência passa a
-- aceitar troca de conta só sob a flag erp.trocar_conta (ligada exclusivamente
-- dentro de efetivar_lancamento); a edição comum continua bloqueada.
-- =============================================================================

create or replace function public.tg_lancamentos_recorrencia()
returns trigger
language plpgsql
set search_path = public
as $$
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
    elsif new.recorrente and new.parcela_atual <> 1 then
      raise exception 'A primeira parcela deve ser a de número 1.' using errcode = 'check_violation';
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
$$;

drop function public.efetivar_lancamento(uuid, date, numeric);

create function public.efetivar_lancamento(p_id uuid, p_data_efetivacao date default current_date, p_encargos numeric default 0, p_conta_id uuid default null)
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
  v_conta_original uuid;
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
  if p_conta_id is not null and p_conta_id <> l.conta_id then
    if l.tipo = 'transferencia' then
      raise exception 'Transferência não muda de conta na baixa.' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from public.contas c where c.id = p_conta_id and c.organizacao_id = l.organizacao_id) then
      raise exception 'Conta inválida para esta organização.' using errcode = 'check_violation';
    end if;
  end if;
  perform set_config('erp.motor', 'on', true);
  v_valor_original := l.valor;
  v_obs_original := l.observacao;
  v_conta_original := l.conta_id;
  if p_conta_id is not null and p_conta_id <> l.conta_id then
    perform set_config('erp.trocar_conta', 'on', true);
    update public.lancamentos set conta_id = p_conta_id where id = p_id;
  end if;
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
  -- encargos e troca de conta são só desta parcela: a próxima (quando gerada aqui) volta ao original
  if n.id is not null then
    update public.lancamentos
       set valor = case when p_encargos > 0 then v_valor_original else valor end,
           observacao = case when p_encargos > 0 then v_obs_original else observacao end,
           conta_id = v_conta_original
     where id = n.id;
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
revoke all on function public.efetivar_lancamento(uuid, date, numeric, uuid) from public, anon;
grant execute on function public.efetivar_lancamento(uuid, date, numeric, uuid) to authenticated;
