-- =============================================================================
-- 0101 · Etapa 58A (ajuste) — sem teto de pontos + campanha com prazo fixo
-- =============================================================================
-- Config final do proprietário (substitui o teto de 30 e a vigência aberta da 0100):
--   pontos = dias_de_antecedência + 1, SEM teto (30 dias antes = 31 pontos, e por aí vai)
--   campanha com prazo fixo: 01/10/2026 a 30/09/2027 — fora dessa janela não gera ponto.
--   "Um ano pra gente ver se funciona, se der certo, prorroga" — extensão é decisão
--   futura do proprietário (nova migration mudando a data final), não automática.
-- =============================================================================

alter table public.pontos_pontualidade drop constraint pontos_pontualidade_pontos_check;
alter table public.pontos_pontualidade add constraint pontos_pontualidade_pontos_check check (pontos > 0);

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
