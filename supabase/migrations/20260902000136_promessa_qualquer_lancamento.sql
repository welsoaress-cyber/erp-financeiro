-- =============================================================================
-- 0136 · Promessa de pagamento em qualquer conta a receber, não só em contrato
-- =============================================================================
-- Pedido do proprietário: cobrança avulsa (sem contrato — ex.: "Ativação
-- Ninja Player") não tinha o botão "🤝 Promessa" em Contas a receber, porque
-- a confiança (0072) só existia presa a contrato_id (seguraria o bloqueio do
-- contrato). "Independentemente de contrato, contas a receber tem que ter
-- promessa."
--
-- confiancas ganha lancamento_id (alternativa a contrato_id — exatamente um
-- dos dois). Contrato continua pelo caminho de sempre (dar_confianca segura
-- o bloqueio do contrato). Lançamento avulso ganha dar_confianca_lancamento:
-- mais simples, só acompanha o prazo — sem bloqueio pra segurar, resolve
-- sozinha quando a cobrança é paga/baixada/cancelada (cumprida) via
-- resolver_confianca_lancamento, chamada no fim de efetivar_lancamento,
-- baixar_parcial e cancelar_lancamento.
-- =============================================================================

alter table public.confiancas alter column contrato_id drop not null;
alter table public.confiancas alter column negocio_id drop not null;
alter table public.confiancas add column lancamento_id uuid references public.lancamentos (id);
alter table public.confiancas add constraint confiancas_alvo_check check ((contrato_id is not null) <> (lancamento_id is not null));
comment on column public.confiancas.lancamento_id is 'Promessa sobre uma cobrança avulsa (sem contrato) — exatamente um entre contrato_id e lancamento_id. Não segura bloqueio (não há contrato); resolve sozinha quando a cobrança é paga/baixada/cancelada.';
create unique index confiancas_ativa_lancamento_unica on public.confiancas (lancamento_id) where status = 'ativa' and lancamento_id is not null;

-- Dar o voto sobre um lançamento avulso (sem contrato). Mesmo prazo máximo (90 dias) da versão por contrato.
create function public.dar_confianca_lancamento(p_lancamento_id uuid, p_segurar_ate date, p_observacao text default null)
returns public.confiancas
language plpgsql
security definer
set search_path = public
as $$
declare l public.lancamentos%rowtype; v public.confiancas%rowtype;
begin
  select * into l from public.lancamentos where id = p_lancamento_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.tipo <> 'receita' then
    raise exception 'Promessa de pagamento só vale para contas a receber.' using errcode = 'check_violation';
  end if;
  if l.status <> 'previsto' then
    raise exception 'Só lançamentos previstos podem receber uma promessa.' using errcode = 'check_violation';
  end if;
  if l.pessoa_id is null then
    raise exception 'Lançamento sem pessoa vinculada não pode receber promessa.' using errcode = 'check_violation';
  end if;
  if p_segurar_ate is null or p_segurar_ate <= current_date then
    raise exception 'A data precisa ser futura.' using errcode = 'check_violation';
  end if;
  if p_segurar_ate > current_date + 90 then
    raise exception 'Promessa de no máximo 90 dias.' using errcode = 'check_violation';
  end if;
  update public.confiancas set status = 'cancelada', resolvido_em = now()
   where lancamento_id = p_lancamento_id and status = 'ativa';
  insert into public.confiancas (organizacao_id, negocio_id, lancamento_id, pessoa_id, segurar_ate, observacao, usuario_id)
  values (l.organizacao_id, l.negocio_id, p_lancamento_id, l.pessoa_id, p_segurar_ate, nullif(trim(p_observacao), ''), auth.uid())
  returning * into v;
  return v;
end;
$$;
revoke all on function public.dar_confianca_lancamento(uuid, date, text) from public, anon;
grant execute on function public.dar_confianca_lancamento(uuid, date, text) to authenticated;

-- Resolve sozinha: cobrança avulsa saiu de "previsto" (pagou, baixa parcial ou cancelou) = promessa cumprida.
create function public.resolver_confianca_lancamento(p_lancamento_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.confiancas set status = 'cumprida', resolvido_em = now()
   where lancamento_id = p_lancamento_id and status = 'ativa';
$$;
revoke all on function public.resolver_confianca_lancamento(uuid) from public, anon, authenticated;

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

  perform public.resolver_confianca_lancamento(l.id);
  return l;
end;
$$;

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
  perform public.resolver_confianca_lancamento(l.id);
  return l;
end;
$$;
revoke all on function public.baixar_parcial(uuid, numeric, date) from public, anon;
grant execute on function public.baixar_parcial(uuid, numeric, date) to authenticated;

create or replace function public.cancelar_lancamento(p_id uuid, p_motivo text default null)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.status = 'cancelado' then
    raise exception 'Lançamento já cancelado.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.lancamentos
     set status = 'cancelado', cancelado_em = now(), motivo_cancelamento = nullif(btrim(coalesce(p_motivo, '')), ''),
         data_efetivacao = null
   where id = p_id returning * into l;
  perform public.gerar_movimentos(l.id); -- remove os movimentos (auditados)
  perform public.resolver_confianca_lancamento(l.id);
  return l;
end;
$$;
