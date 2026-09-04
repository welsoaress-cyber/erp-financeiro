-- =============================================================================
-- 0029 · Projeção de recorrência + edição em lote (esta / futuras / todas)
-- =============================================================================
-- Etapa 16, itens 2 e 4 (item 1 — pendências de meses anteriores — e item 3 —
-- excluir lançamento previsto — já existem: excluir_lancamento (migration 0005)
-- já apaga de verdade, só para status = 'previsto'; a lista de pendências
-- anteriores é uma consulta no app, sem precisar de banco novo).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Projeção: gera N meses à frente de uma recorrência, sem exigir que a atual
-- esteja paga. Igual à gerar_proxima_parcela (motor interno de sempre), mas
-- sem a exigência de status = 'efetivado' — função separada para não mudar o
-- comportamento de quem paga uma parcela (continua gerando só a seguinte).
-- -----------------------------------------------------------------------------
create or replace function public.gerar_proxima_parcela_projetada(p_id uuid)
returns public.lancamentos
language plpgsql
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  n public.lancamentos%rowtype;
  v_raiz_venc date;
  v_venc date;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found or not l.recorrente or l.status = 'cancelado' then return null; end if;
  if exists (select 1 from public.lancamentos f where f.lancamento_origem_id = l.id) then return null; end if;
  if l.numero_parcelas is not null and l.parcela_atual >= l.numero_parcelas then return null; end if;

  with recursive cadeia as (
    select id, lancamento_origem_id, data_vencimento from public.lancamentos where id = l.id
    union all
    select p.id, p.lancamento_origem_id, p.data_vencimento from public.lancamentos p join cadeia c on p.id = c.lancamento_origem_id
  )
  select data_vencimento into v_raiz_venc from cadeia where lancamento_origem_id is null;

  v_venc := public.proxima_data_recorrencia(l.data_vencimento, l.periodicidade, extract(day from coalesce(v_raiz_venc, l.data_vencimento))::int);
  if l.data_fim_recorrencia is not null and v_venc > l.data_fim_recorrencia then return null; end if;

  insert into public.lancamentos (
    organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
    conta_id, conta_destino_id, categoria_id, observacao, origem, negocio_id, pessoa_id, contrato_id,
    recorrente, periodicidade, numero_parcelas, parcela_atual, data_fim_recorrencia, lancamento_origem_id
  ) values (
    l.organizacao_id, l.tipo, l.descricao, l.valor, v_venc - (l.data_vencimento - l.data_competencia), v_venc, null, 'previsto',
    l.conta_id, l.conta_destino_id, l.categoria_id, l.observacao, l.origem, l.negocio_id, l.pessoa_id, l.contrato_id,
    true, l.periodicidade, l.numero_parcelas, l.parcela_atual + 1, l.data_fim_recorrencia, l.id
  ) returning * into n;
  return n;
end;
$$;

-- Chamada pelo cliente: projeta a partir da ponta atual da cadeia (o último já gerado),
-- até p_meses parcelas à frente (menos, se bater no fim do parcelamento ou na data-limite).
create or replace function public.projetar_lancamento(p_id uuid, p_meses integer default 6)
returns setof public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  tip public.lancamentos%rowtype;
  n public.lancamentos%rowtype;
  i integer;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if not l.recorrente then raise exception 'Este lançamento não é recorrente.' using errcode = 'check_violation'; end if;
  if p_meses is null or p_meses < 1 or p_meses > 60 then raise exception 'Horizonte de projeção entre 1 e 60 meses.' using errcode = 'check_violation'; end if;

  perform set_config('erp.motor', 'on', true);
  with recursive cadeia as (
    select * from public.lancamentos where id = l.id
    union all
    select f.* from public.lancamentos f join cadeia c on f.lancamento_origem_id = c.id
  )
  select * into tip from cadeia order by parcela_atual desc limit 1;

  for i in 1..p_meses loop
    n := public.gerar_proxima_parcela_projetada(tip.id);
    exit when n.id is null;
    tip := n;
  end loop;

  return query
    with recursive cadeia as (
      select * from public.lancamentos where id = l.id
      union all
      select f.* from public.lancamentos f join cadeia c on f.lancamento_origem_id = c.id
    )
    select * from cadeia order by parcela_atual;
end;
$$;

-- -----------------------------------------------------------------------------
-- Edição em lote de uma recorrência: descrição, valor e observação (os únicos
-- campos que uma parcela com filhas já pode alterar) em escopo 'atual' (só esta),
-- 'futuras' (esta e as seguintes da cadeia, sem tocar nas anteriores) ou 'todas'
-- (a cadeia inteira, inclusive já pagas — reprocessa os movimentos de cada uma
-- que já estiver efetivada, para o saldo continuar batendo).
-- -----------------------------------------------------------------------------
create or replace function public.atualizar_lancamento_recorrente(
  p_id uuid, p_descricao text, p_valor numeric, p_observacao text, p_escopo text default 'atual'
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

  perform set_config('erp.motor', 'on', true);

  if p_escopo = 'atual' then
    update public.lancamentos set descricao = btrim(p_descricao), valor = p_valor, observacao = v_obs where id = p_id;
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

  for r in
    with recursive cadeia as (
      select id, status from public.lancamentos where id = v_raiz
      union all
      select f.id, f.status from public.lancamentos f join cadeia c on f.lancamento_origem_id = c.id
    )
    select id, status from cadeia where status <> 'cancelado'
  loop
    update public.lancamentos set descricao = btrim(p_descricao), valor = p_valor, observacao = v_obs where id = r.id;
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

revoke all on function public.gerar_proxima_parcela_projetada(uuid) from public, anon, authenticated;
revoke all on function public.projetar_lancamento(uuid, integer) from public, anon;
grant execute on function public.projetar_lancamento(uuid, integer) to authenticated;
revoke all on function public.atualizar_lancamento_recorrente(uuid, text, numeric, text, text) from public, anon;
grant execute on function public.atualizar_lancamento_recorrente(uuid, text, numeric, text, text) to authenticated;
