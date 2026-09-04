-- =============================================================================
-- 0031 · Projeção de contratos: meses futuros visíveis sem gravar lançamento
-- =============================================================================
-- Contratos faturam mês a mês (fidelidade, descontos e encerramento dependem
-- disso). Para o usuário enxergar a receita/despesa do contrato nos meses
-- futuros, esta função DERIVA a projeção na hora — sempre com o valor e o
-- status atuais do contrato — sem inserir nada em lancamentos/faturamentos.
-- O lançamento real continua nascendo no mês certo pelo cron/trigger.
-- =============================================================================

create or replace function public.projecao_contratos(p_organizacao uuid, p_de date, p_ate date)
returns table (
  contrato_id uuid,
  negocio_id uuid,
  pessoa_id uuid,
  conta_id uuid,
  categoria_id uuid,
  tipo public.tipo_lancamento,
  descricao text,
  valor numeric(14,2),
  data_competencia date,
  data_vencimento date
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.exigir_membro(p_organizacao);
  if p_de is null or p_ate is null or p_ate < p_de then
    raise exception 'Período inválido.' using errcode = 'check_violation';
  end if;
  if p_ate > (date_trunc('month', current_date) + interval '61 months')::date then
    raise exception 'Horizonte de projeção: no máximo 60 meses à frente.' using errcode = 'check_violation';
  end if;
  return query
    select c.id,
           c.negocio_id,
           c.pessoa_id,
           coalesce(c.conta_id, n.conta_padrao_id),
           case when c.tipo_financeiro = 'despesa' then n.categoria_despesa_id else n.categoria_receita_id end,
           c.tipo_financeiro::text::public.tipo_lancamento,
           left(pl.nome || ' · ' || to_char(comp, 'MM/YYYY') || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140),
           c.valor,
           public.data_vencimento_no_mes(comp, c.dia_vencimento),
           public.data_vencimento_no_mes(comp, c.dia_vencimento)
    from public.contratos c
    join public.negocios n on n.id = c.negocio_id
    join public.planos pl on pl.id = c.plano_id
    cross join lateral public.competencias_pendentes(c.id, p_ate) comp
    where c.organizacao_id = p_organizacao
      and c.status = 'ativo'
      and c.faturamento_automatico
      and c.valor > 0
      -- só meses estritamente futuros: corrente e atrasados são do motor real
      and comp > date_trunc('month', current_date)::date
      and comp >= date_trunc('month', p_de)::date
    order by 9, 7;
end;
$$;
comment on function public.projecao_contratos(uuid, date, date) is
  'Projeção derivada dos contratos ativos com faturamento automático: competências futuras ainda não faturadas, a valor atual. Nada é gravado.';

revoke all on function public.projecao_contratos(uuid, date, date) from public, anon;
grant execute on function public.projecao_contratos(uuid, date, date) to authenticated;
