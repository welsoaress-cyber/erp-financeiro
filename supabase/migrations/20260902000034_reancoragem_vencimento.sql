-- =============================================================================
-- 0034 · Pagamento em atraso reancora os próximos vencimentos
-- =============================================================================
-- Regra do proprietário: se o cliente pagou atrasado, o ciclo recomeça na data
-- paga. Ex.: vencia 30/08, pagou 04/09 → próximos vencimentos 04/10, 04/11...
-- Vale para recorrências (fixa/parcelada: a cadeia prevista desloca) e para
-- cobranças de contrato (dia_vencimento do contrato passa a ser o dia pago —
-- faturamento futuro e projeção seguem sozinhos). Pagamento em dia ou
-- adiantado não muda nada.
-- =============================================================================

create or replace function public.reancorar_recorrencia(p_id uuid, p_base date)
returns void
language plpgsql
set search_path = public
as $$
declare
  r record;
  v_venc date;
  v_dia int := extract(day from p_base)::int;
begin
  perform set_config('erp.motor', 'on', true);
  perform set_config('erp.editar_data', 'on', true);
  v_venc := p_base;
  for r in
    with recursive cadeia as (
      select id, status, data_vencimento, data_competencia, periodicidade, parcela_atual
        from public.lancamentos where lancamento_origem_id = p_id
      union all
      select f.id, f.status, f.data_vencimento, f.data_competencia, f.periodicidade, f.parcela_atual
        from public.lancamentos f join cadeia c on f.lancamento_origem_id = c.id
    )
    select * from cadeia where status <> 'cancelado' order by parcela_atual
  loop
    -- régua avança sempre; só parcelas previstas mudam de data
    v_venc := public.proxima_data_recorrencia(v_venc, r.periodicidade, v_dia);
    if r.status = 'previsto' then
      update public.lancamentos
         set data_vencimento = v_venc,
             data_competencia = v_venc - (r.data_vencimento - r.data_competencia)
       where id = r.id;
    end if;
  end loop;
end;
$$;
revoke all on function public.reancorar_recorrencia(uuid, date) from public, anon, authenticated;

create or replace function public.efetivar_lancamento(p_id uuid, p_data_efetivacao date default current_date)
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
  if l.status <> 'previsto' then
    raise exception 'Somente lançamentos previstos podem ser efetivados.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.lancamentos set status = 'efetivado', data_efetivacao = p_data_efetivacao where id = p_id returning * into l;
  perform public.gerar_movimentos(l.id);
  perform public.gerar_proxima_parcela(l.id);
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
revoke all on function public.efetivar_lancamento(uuid, date) from public, anon;
grant execute on function public.efetivar_lancamento(uuid, date) to authenticated;
