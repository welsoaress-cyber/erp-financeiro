-- =============================================================================
-- 0087 · CARTÃO DE CRÉDITO — dia útil, limite comprometido, saldo sincronizado
-- =============================================================================
-- Três lacunas apontadas pelo dono:
-- 1) Fechamento/vencimento caindo em sábado/domingo deve antecipar para o dia
--    útil anterior (sem tabela de feriados — não há fonte gratuita confiável).
-- 2) "Disponível" hoje só descontava despesas já efetivadas; parcelas futuras
--    (ainda previstas) não comprometiam o limite. vw_cartoes_limite corrige.
-- 3) "Disponível" não deve mais depender de conta.saldo_inicial — a trigger
--    contas_protecao trava saldo_inicial assim que a conta tem QUALQUER
--    movimento (regra de integridade: não se reescreve o saldo de partida
--    de uma conta já usada). Um cartão quase sempre já tem movimento, então
--    sincronizar saldo_inicial = limite (como o comentário da 0038 dizia)
--    bateria nessa trava direto. Solução: vw_cartoes_limite calcula o
--    disponível puro do limite + uso líquido já efetivado, sem tocar em
--    saldo_inicial nenhuma vez.
--
-- Efeito colateral corrigido de tabela: fechar_fatura_cartao comparava
-- data_vencimento das parcelas contra o dia de FECHAMENTO (v_fech) — mas
-- data_vencimento já é o vencimento real da FATURA (ex.: 25), sempre maior
-- que o fechamento (ex.: 16); a condição nunca batia. Passa a comparar por
-- igualdade com o vencimento da fatura (v_venc).
--
-- IMPORTANTE — v_venc de CASAMENTO fica sem ajuste de dia útil: cada parcela
-- futura de uma compra parcelada já nasce pré-gerada por projetar_lancamento
-- (recorrência genérica, usada por toda a base — mensalidade, contrato etc.),
-- que soma "+1 mês" no calendário puro, sem saber de fim de semana. Se eu
-- ajustasse a data usada para casar previstas com a fatura, uma parcela cujo
-- dia 25 cai num domingo (ex.: 25/10/2026) nunca bateria com o v_venc
-- ajustado (23/10) e ficaria "previsto" pra sempre, sem fechar. Por isso o
-- ajuste de dia útil entra só na data de vencimento DA FATURA em si
-- (v_venc_real, o que o dono vê e paga) — o casamento das parcelas continua
-- pelo calendário puro (v_venc), igual ao que vencimentoFatura() já grava
-- em cada parcela no app (sem ajuste — mesma regra dos dois lados).
-- =============================================================================

create or replace function public.ajustar_dia_util(p_data date)
returns date
language sql
immutable
set search_path = public
as $$
  select case extract(dow from p_data)
    when 0 then p_data - 2  -- domingo → sexta anterior
    when 6 then p_data - 1  -- sábado → sexta anterior
    else p_data
  end;
$$;

create or replace function public.fechar_fatura_cartao(p_conta uuid, p_ref date default current_date)
returns public.faturas
language plpgsql
set search_path = public
as $$
declare
  cfg public.cartoes_config%rowtype;
  v_fech date; v_ini date; v_venc date; v_venc_real date;
  f public.faturas%rowtype;
  r record;
  v_total numeric(14,2);
begin
  select * into cfg from public.cartoes_config where conta_id = p_conta;
  if not found then return null; end if;
  -- último fechamento ocorrido até p_ref (calendário puro — só de referência, não usado para casar parcela)
  v_fech := public.data_vencimento_no_mes(date_trunc('month', p_ref)::date, cfg.dia_fechamento);
  if v_fech > p_ref then
    v_fech := public.data_vencimento_no_mes((date_trunc('month', p_ref) - interval '1 month')::date, cfg.dia_fechamento);
  end if;
  if exists (select 1 from public.faturas x where x.conta_id = p_conta and x.periodo_fim = v_fech) then
    select * into f from public.faturas x where x.conta_id = p_conta and x.periodo_fim = v_fech;
    return f;
  end if;
  v_ini := (public.data_vencimento_no_mes((v_fech - interval '1 month')::date, cfg.dia_fechamento) + 1)::date;
  -- v_venc (calendário puro): chave de casamento com as parcelas, igual ao que vencimentoFatura() grava no app
  v_venc := public.data_vencimento_no_mes(date_trunc('month', v_fech)::date, cfg.dia_vencimento);
  if v_venc <= v_fech then
    v_venc := public.data_vencimento_no_mes((date_trunc('month', v_fech) + interval '1 month')::date, cfg.dia_vencimento);
  end if;
  -- v_venc_real (ajustado): o que vai pra faturas.data_vencimento — data de verdade que o dono paga
  v_venc_real := public.ajustar_dia_util(v_venc);

  perform set_config('erp.motor', 'on', true);

  -- parcelas previstas com vencimento igual ao desta fatura viram efetivadas (consomem limite);
  -- data_vencimento já É o vencimento da fatura (vencimentoFatura() no app grava esse valor).
  for r in
    select l.id, l.data_vencimento from public.lancamentos l
     where l.conta_id = p_conta and l.tipo = 'despesa' and l.status = 'previsto'
       and l.data_vencimento = v_venc
     order by l.data_vencimento
  loop
    update public.lancamentos set status = 'efetivado', data_efetivacao = r.data_vencimento where id = r.id;
    perform public.gerar_movimentos(r.id);
    perform public.gerar_proxima_parcela(r.id);
  end loop;

  select coalesce(sum(l.valor), 0) into v_total
    from public.lancamentos l
   where l.conta_id = p_conta and l.tipo = 'despesa' and l.status = 'efetivado'
     and l.data_efetivacao = v_venc
     and not exists (select 1 from public.fatura_itens i where i.lancamento_id = l.id);
  if v_total = 0 then return null; end if;

  insert into public.faturas (organizacao_id, conta_id, periodo_inicio, periodo_fim, data_vencimento, valor_total)
  values (cfg.organizacao_id, p_conta, v_ini, v_fech, v_venc_real, v_total)
  returning * into f;

  insert into public.fatura_itens (organizacao_id, fatura_id, lancamento_id)
  select cfg.organizacao_id, f.id, l.id
    from public.lancamentos l
   where l.conta_id = p_conta and l.tipo = 'despesa' and l.status = 'efetivado'
     and l.data_efetivacao = v_venc
     and not exists (select 1 from public.fatura_itens i where i.lancamento_id = l.id);
  return f;
end;
$$;

-- -----------------------------------------------------------------------------
-- Limite comprometido e disponível — calculado puro do limite, sem depender
-- de saldo_inicial: disponível = limite − (uso já efetivado líquido) −
-- (parcelas futuras ainda previstas). "Uso líquido" soma despesas efetivadas
-- e subtrai pagamentos de fatura (transferência credita a conta do cartão,
-- restaurando limite — já é assim hoje).
-- -----------------------------------------------------------------------------
create view public.vw_cartoes_limite
with (security_invoker = true) as
select k.id as config_id, k.conta_id, k.organizacao_id, k.limite_total,
       coalesce(u.uso_liquido, 0)::numeric(14,2) as uso_efetivado,
       coalesce(p.comprometido, 0)::numeric(14,2) as comprometido,
       round(k.limite_total + coalesce(u.uso_liquido, 0) - coalesce(p.comprometido, 0), 2)::numeric(14,2) as disponivel
  from public.cartoes_config k
  left join (
    select conta_id, sum(valor) as uso_liquido from public.movimentos group by conta_id
  ) u on u.conta_id = k.conta_id
  left join (
    select conta_id, sum(valor) as comprometido
      from public.lancamentos
     where tipo = 'despesa' and status = 'previsto'
     group by conta_id
  ) p on p.conta_id = k.conta_id;
grant select on public.vw_cartoes_limite to authenticated;
