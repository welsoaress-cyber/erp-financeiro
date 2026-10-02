-- =============================================================================
-- 0122 · Reancoragem precisa valer mesmo com o contrato suspenso
-- =============================================================================
-- Bug desde a 0034: o update de contratos.dia_vencimento na reancoragem só
-- rodava com `status = 'ativo'`. Contrato suspenso (inadimplente, que acabou
-- de pagar e AINDA não foi reativado — a baixa não reativa sozinha) nunca
-- tinha o dia_vencimento atualizado: a cobrança seguinte continuava
-- calculada pelo dia antigo. Caso real: contrato #032 pago atrasado em
-- 01/10, ainda suspenso — dia_vencimento ficou 29 (não virou 1), e a
-- projeção de novembro saiu errada (29/11 em vez de 01/12).
--
-- Troca `status = 'ativo'` por `status <> 'encerrado'`: contrato encerrado
-- nunca mais recebe faturamento, então seu dia_vencimento não importa mais
-- (não muda); qualquer outro status (ativo ou suspenso) reancora
-- normalmente — o pagamento já aconteceu, independente do contrato estar
-- reativado ou não.
-- =============================================================================

create or replace function public.efetivar_lancamento(p_id uuid, p_data_efetivacao date default current_date, p_encargos numeric default 0, p_conta_id uuid default null)
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
  v_contrato public.contratos%rowtype;
  v_pontos_ativo boolean;
  v_dias int;
  v_pontos int;
  v_dia smallint;
  v_prepago boolean;
  v_periodicidade public.periodicidade;
  v_intervalo interval;
  v_cursor date;
  v_fut record;
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
      select c.periodicidade, n2.ciclo_prepago into v_periodicidade, v_prepago
        from public.contratos c join public.negocios n2 on n2.id = c.negocio_id
       where c.id = l.contrato_id;
      if v_prepago then
        -- próxima fatura (e as seguintes já geradas) encadeiam a partir do pagamento + 1 período,
        -- não do dia do mês: pagou atrasado, as 30 dias de acesso contam a partir de agora.
        v_intervalo := case v_periodicidade when 'anual' then interval '1 year' else interval '1 month' end;
        v_cursor := p_data_efetivacao + v_intervalo;
        v_dia := least(extract(day from v_cursor)::int, 31)::smallint;
        update public.contratos set dia_vencimento = v_dia where id = l.contrato_id and status <> 'encerrado';
        for v_fut in
          select id from public.lancamentos
           where contrato_id = l.contrato_id and status = 'previsto' and data_competencia > l.data_competencia
           order by data_competencia asc
        loop
          update public.lancamentos set data_vencimento = v_cursor where id = v_fut.id;
          v_cursor := v_cursor + v_intervalo;
        end loop;
      else
        v_dia := least(extract(day from p_data_efetivacao)::int, 31)::smallint;
        update public.contratos set dia_vencimento = v_dia where id = l.contrato_id and status <> 'encerrado';
        -- faturas futuras do mesmo contrato que já tinham sido geradas (ainda previstas)
        -- acompanham o novo dia na mesma baixa — não só o que o faturamento ainda vai gerar.
        update public.lancamentos
           set data_vencimento = public.data_vencimento_no_mes(data_competencia, v_dia)
         where contrato_id = l.contrato_id and status = 'previsto' and data_competencia > l.data_competencia;
      end if;
    end if;
  end if;

  -- pontos por pontualidade (58A, ajustado na 0101): só quitação total de contrato de receita
  -- elegível, negócio com o programa ligado, e dentro da janela da campanha (01/10/2026 a 30/09/2027)
  if l.tipo = 'receita' and l.contrato_id is not null
     and p_data_efetivacao between date '2026-10-01' and date '2027-09-30' then
    select * into v_contrato from public.contratos where id = l.contrato_id;
    select coalesce(pontos_ativo, false) into v_pontos_ativo from public.notificacoes_config where negocio_id = l.negocio_id;
    if v_contrato.id is not null and v_contrato.tipo_financeiro = 'receita' and v_contrato.elegivel_pontos and v_pontos_ativo then
      v_dias := l.data_vencimento_original - p_data_efetivacao;
      if v_dias >= 0 then
        v_pontos := v_dias + 1; -- sem teto (config final do proprietário)
        insert into public.pontos_pontualidade (organizacao_id, negocio_id, pessoa_id, contrato_id, lancamento_id, ciclo_inicio, pontos)
        values (l.organizacao_id, l.negocio_id, l.pessoa_id, l.contrato_id, l.id, public.ciclo_pontos_inicio(p_data_efetivacao), v_pontos);
      end if;
    end if;
  end if;

  return l;
end;
$$;
