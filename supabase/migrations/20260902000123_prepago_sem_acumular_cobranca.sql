-- =============================================================================
-- 0123 · Negócio pré-pago nunca acumula cobrança em aberto
-- =============================================================================
-- Revenda pré-paga (Servidor Toptv/Uniplay): sem fidelidade, sem obrigação de
-- renovar. Se o cliente não pagou o mês corrente, o faturamento automático
-- não pode gerar a cobrança do mês seguinte em cima — ele não vai pagar duas
-- pra usar uma. `faturar_contrato` (negócio com `ciclo_prepago`) passa a:
--   - nunca ter mais de UMA cobrança 'previsto' em aberto por contrato: se já
--     existe uma (vencida ou não), não gera a próxima;
--   - se por algum motivo já tiver mais de uma em aberto (dado antigo, ou
--     faturamento que rodou atrasado e preencheu vários meses de uma vez),
--     mantém só a mais antiga (a dívida real) e cancela as demais — motivo
--     registrado no lançamento, nunca silencioso.
-- Negócio comum (internet/provedor, `ciclo_prepago = false`) não muda nada:
-- continua podendo faturar vários meses à frente.
-- =============================================================================

create or replace function public.faturar_contrato(p_contrato uuid, p_ate date, out gerados integer, out pendencia text)
language plpgsql
set search_path = public
as $$
declare
  c public.contratos%rowtype;
  n public.negocios%rowtype;
  pl public.planos%rowtype;
  v_conta uuid; v_cat uuid; v_comp date; v_venc date; l public.lancamentos%rowtype;
  v_desc numeric(14,2); v_valor numeric(14,2); v_motivos text;
  v_tem_aberta boolean;
begin
  gerados := 0; pendencia := null;
  select * into c from public.contratos where id = p_contrato;
  if not found or c.status <> 'ativo' or not c.faturamento_automatico then return; end if;
  if not exists (select 1 from public.competencias_pendentes(c.id, p_ate)) then return; end if;
  select * into n from public.negocios where id = c.negocio_id;
  if n.ciclo_prepago then
    v_tem_aberta := false;
    for l in select * from public.lancamentos where contrato_id = c.id and status = 'previsto' order by data_competencia loop
      if v_tem_aberta then
        perform public.cancelar_lancamento(l.id, 'Negócio pré-pago: só uma cobrança em aberto por vez.');
      else
        v_tem_aberta := true;
      end if;
    end loop;
    if v_tem_aberta then return; end if;
  end if;
  select * into pl from public.planos where id = c.plano_id;
  v_conta := coalesce(c.conta_id, n.conta_padrao_id);
  v_cat := case when c.tipo_financeiro = 'despesa' then n.categoria_despesa_id else n.categoria_receita_id end;
  if v_conta is null then pendencia := case when c.tipo_financeiro = 'despesa' then 'Sem conta de pagamento (no contrato ou padrão do negócio).' else 'Sem conta de recebimento (no contrato ou padrão do negócio).' end; return; end if;
  if v_cat is null then pendencia := case when c.tipo_financeiro = 'despesa' then 'Negócio sem categoria de despesa padrão.' else 'Negócio sem categoria de receita padrão.' end; return; end if;
  if not exists (select 1 from public.contas where id = v_conta and ativo) then pendencia := case when c.tipo_financeiro = 'despesa' then 'Conta de pagamento inativa.' else 'Conta de recebimento inativa.' end; return; end if;
  if not exists (select 1 from public.categorias where id = v_cat and ativo) then pendencia := 'Categoria padrão inativa.'; return; end if;
  if c.cortesia then
    -- cortesia (0080): a fatura aparece, mas não conta — nasce CANCELADA (mesmo caminho do "mês grátis"),
    -- com o valor de tabela do plano só como referência. Cancelado não entra em previsto/realizado/saldo,
    -- cobrança nem bloqueio; o portal mostra "Grátis". Plano com valor de tabela 0: nada a mostrar.
    if coalesce(pl.valor_tabela, 0) <= 0 then return; end if;
    perform set_config('erp.motor', 'on', true);
    for v_comp in select * from public.competencias_pendentes(c.id, p_ate) order by 1 limit (case when n.ciclo_prepago then 1 end) loop
      v_venc := public.data_vencimento_no_mes(v_comp, c.dia_vencimento);
      insert into public.lancamentos (
        organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
        conta_id, categoria_id, origem, negocio_id, pessoa_id, contrato_id, observacao, cancelado_em, motivo_cancelamento, centro_custo_id
      ) values (
        c.organizacao_id, c.tipo_financeiro::text::public.tipo_lancamento,
        left(pl.nome || ' · ' || to_char(v_comp, 'MM/YYYY') || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140),
        pl.valor_tabela, v_venc, v_venc, null, 'cancelado',
        v_conta, v_cat, 'faturamento', c.negocio_id, c.pessoa_id, c.id,
        'Cortesia (sem cobrança).', now(), 'Cortesia', c.centro_custo_id
      ) returning * into l;
      insert into public.faturamentos (organizacao_id, contrato_id, competencia, lancamento_id) values (c.organizacao_id, c.id, v_comp, l.id);
      gerados := gerados + 1;
    end loop;
    return;
  end if;
  if c.valor <= 0 then pendencia := 'Contrato com valor zero.'; return; end if;

  perform set_config('erp.motor', 'on', true);
  for v_comp in select * from public.competencias_pendentes(c.id, p_ate) order by 1 limit (case when n.ciclo_prepago then 1 end) loop
    v_venc := public.data_vencimento_no_mes(v_comp, c.dia_vencimento);
    if c.tipo_financeiro = 'receita' then
      perform public.fidelidade_registrar_premio(c.id, v_comp);
      select coalesce(sum(d.valor), 0), string_agg(d.motivo, '; ' order by d.criado_em) into v_desc, v_motivos
        from public.descontos_contrato d where d.contrato_id = c.id and d.lancamento_id is null;
    else
      v_desc := 0; v_motivos := null;
    end if;
    v_valor := case when v_desc >= c.valor then c.valor else c.valor - v_desc end;
    insert into public.lancamentos (
      organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
      conta_id, categoria_id, origem, negocio_id, pessoa_id, contrato_id, observacao, cancelado_em, motivo_cancelamento, centro_custo_id
    ) values (
      c.organizacao_id, c.tipo_financeiro::text::public.tipo_lancamento,
      left(pl.nome || ' · ' || to_char(v_comp, 'MM/YYYY') || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140),
      v_valor, v_venc, v_venc, null, (case when v_desc >= c.valor then 'cancelado' else 'previsto' end)::public.status_lancamento,
      v_conta, v_cat, 'faturamento', c.negocio_id, c.pessoa_id, c.id,
      case when v_desc >= c.valor then left('Mês grátis (' || v_motivos || ').', 500)
           when v_desc > 0 then left('Desconto aplicado: ' || public.moeda_br(v_desc) || ' (' || v_motivos || ').', 500) end,
      case when v_desc >= c.valor then now() end,
      case when v_desc >= c.valor then left('Mês grátis: ' || v_motivos, 200) end,
      c.centro_custo_id
    ) returning * into l;
    if v_desc > 0 then
      update public.descontos_contrato set lancamento_id = l.id where contrato_id = c.id and lancamento_id is null;
    end if;
    insert into public.faturamentos (organizacao_id, contrato_id, competencia, lancamento_id) values (c.organizacao_id, c.id, v_comp, l.id);
    gerados := gerados + 1;
  end loop;
end;
$$;
