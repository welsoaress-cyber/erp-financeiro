-- =============================================================================
-- 0032 · Edição de DATA em recorrência com parcelas já geradas
-- =============================================================================
-- Com a projeção automática (60 meses ao criar), toda recorrência nasce com as
-- parcelas seguintes geradas — e a regra antiga travava a data na hora. Agora
-- a data pode mudar nos escopos 'atual' (só esta parcela, se prevista) e
-- 'futuras' (esta e as seguintes previstas deslocam para o novo dia). 'todas'
-- continua sem mexer em data (reescrever data de parcela paga não faz sentido).
-- =============================================================================

-- O trigger da 0025 travava data em parcela com filhas. Continua travando fora
-- do motor; a flag de sessão erp.editar_data (ligada só dentro de
-- atualizar_lancamento_recorrente) libera exclusivamente as duas datas.
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
    if new.conta_id <> old.conta_id or new.conta_destino_id is distinct from old.conta_destino_id
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

drop function public.atualizar_lancamento_recorrente(uuid, text, numeric, text, text);

create function public.atualizar_lancamento_recorrente(
  p_id uuid, p_descricao text, p_valor numeric, p_observacao text, p_escopo text default 'atual',
  p_data_vencimento date default null
)
returns setof public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  v_raiz uuid;
  v_obs text := nullif(btrim(coalesce(p_observacao, '')), '');
  v_venc date;
  v_dia int;
  r record;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if not l.recorrente then raise exception 'Este lançamento não é recorrente.' using errcode = 'check_violation'; end if;
  if l.status = 'cancelado' then raise exception 'Lançamento cancelado não pode ser alterado.' using errcode = 'check_violation'; end if;
  if p_escopo not in ('atual', 'futuras', 'todas') then raise exception 'Escopo inválido.' using errcode = 'check_violation'; end if;
  if btrim(coalesce(p_descricao, '')) = '' then raise exception 'Informe a descrição.' using errcode = 'check_violation'; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'Informe um valor maior que zero.' using errcode = 'check_violation'; end if;
  if p_data_vencimento is not null and p_escopo = 'todas' then
    raise exception 'Data só pode mudar em "apenas esta" ou "esta e as futuras".' using errcode = 'check_violation';
  end if;
  if p_data_vencimento is not null and l.status <> 'previsto' then
    raise exception 'Só lançamento previsto pode mudar de data.' using errcode = 'check_violation';
  end if;

  perform set_config('erp.motor', 'on', true);
  if p_data_vencimento is not null then perform set_config('erp.editar_data', 'on', true); end if;

  if p_escopo = 'atual' then
    update public.lancamentos set descricao = btrim(p_descricao), valor = p_valor, observacao = v_obs where id = p_id;
    if p_data_vencimento is not null then
      update public.lancamentos
         set data_vencimento = p_data_vencimento,
             data_competencia = p_data_vencimento - (data_vencimento - data_competencia)
       where id = p_id;
    end if;
    perform public.gerar_movimentos(p_id);
    return query select * from public.lancamentos where id = p_id;
    return;
  end if;

  if p_escopo = 'todas' then
    with recursive raiz as (
      select id, lancamento_origem_id from public.lancamentos where id = p_id
      union all
      select pai.id, pai.lancamento_origem_id from public.lancamentos pai join raiz c on pai.id = c.lancamento_origem_id
    )
    select id into v_raiz from raiz where lancamento_origem_id is null;
  else
    v_raiz := p_id; -- 'futuras': nunca sobe para trás, só desce a partir desta
  end if;

  v_venc := p_data_vencimento;
  v_dia := case when p_data_vencimento is not null then extract(day from p_data_vencimento)::int end;
  for r in
    with recursive cadeia as (
      select id, status, data_vencimento, data_competencia, periodicidade, parcela_atual, 0 as nivel
        from public.lancamentos where id = v_raiz
      union all
      select f.id, f.status, f.data_vencimento, f.data_competencia, f.periodicidade, f.parcela_atual, c.nivel + 1
        from public.lancamentos f join cadeia c on f.lancamento_origem_id = c.id
    )
    select * from cadeia where status <> 'cancelado' order by parcela_atual
  loop
    update public.lancamentos set descricao = btrim(p_descricao), valor = p_valor, observacao = v_obs where id = r.id;
    if p_data_vencimento is not null then
      -- desloca as datas: a parcela editada recebe a nova data e as seguintes
      -- avançam a partir dela no novo dia âncora; parcelas já pagas não movem,
      -- mas a régua continua avançando para as previstas depois delas
      if r.nivel > 0 then
        v_venc := public.proxima_data_recorrencia(v_venc, r.periodicidade, v_dia);
      end if;
      if r.status = 'previsto' then
        update public.lancamentos
           set data_vencimento = v_venc,
               data_competencia = v_venc - (r.data_vencimento - r.data_competencia)
         where id = r.id;
      end if;
    end if;
    if r.status = 'efetivado' then perform public.gerar_movimentos(r.id); end if;
  end loop;

  return query
    with recursive cadeia as (
      select * from public.lancamentos where id = v_raiz
      union all
      select f.* from public.lancamentos f join cadeia c on f.lancamento_origem_id = c.id
    )
    select * from cadeia order by parcela_atual;
end;
$$;

revoke all on function public.atualizar_lancamento_recorrente(uuid, text, numeric, text, text, date) from public, anon;
grant execute on function public.atualizar_lancamento_recorrente(uuid, text, numeric, text, text, date) to authenticated;
