-- =============================================================================
-- 0069 · Etapa 43 — Estorno formal de lançamento efetivado
-- =============================================================================
-- Corrigir um efetivado errado sem reescrever o passado: o estorno cria um
-- CONTRA-LANÇAMENTO datado de hoje, do mesmo tipo e categoria, com valor
-- NEGATIVO — o caixa volta hoje, o resultado do mês atual é corrigido e o
-- lançamento original (mesmo em mês fechado) fica intocado, com a trilha
-- completa. gerar_movimentos já inverte o caixa sozinho pelo sinal.
-- Um efetivado só pode ser estornado uma vez; estorno não se estorna
-- (cancele o estorno se ele próprio estiver errado).
-- =============================================================================

alter type public.origem_lancamento add value if not exists 'estorno';

alter table public.lancamentos drop constraint lancamentos_valor_check;
alter table public.lancamentos add constraint lancamentos_valor_check
  check (valor > 0 or (origem::text = 'estorno' and valor < 0));

alter table public.lancamentos add column estorno_de uuid references public.lancamentos (id) on delete restrict;
create unique index lancamentos_estorno_unico on public.lancamentos (estorno_de)
  where estorno_de is not null and status <> 'cancelado'; -- estorno cancelado libera estornar de novo
comment on column public.lancamentos.estorno_de is 'Aponta o lançamento efetivado que este estorno corrige (um estorno por lançamento).';

create function public.estornar_lancamento(p_id uuid, p_motivo text)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare l public.lancamentos%rowtype; e public.lancamentos%rowtype;
begin
  select * into l from public.lancamentos where id = p_id for update;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.status <> 'efetivado' then
    raise exception 'Só lançamento efetivado pode ser estornado (previsto se cancela).' using errcode = 'check_violation';
  end if;
  if l.origem::text = 'estorno' then
    raise exception 'Estorno não se estorna — cancele o estorno se ele estiver errado.' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.lancamentos where estorno_de = l.id and status <> 'cancelado') then
    raise exception 'Este lançamento já foi estornado.' using errcode = 'check_violation';
  end if;
  if p_motivo is null or char_length(btrim(p_motivo)) < 5 then
    raise exception 'Informe o motivo do estorno (mínimo 5 caracteres).' using errcode = 'check_violation';
  end if;

  perform set_config('erp.motor', 'on', true);
  insert into public.lancamentos (
    organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao,
    status, conta_id, conta_destino_id, categoria_id, observacao, origem,
    negocio_id, pessoa_id, contrato_id, estorno_de
  ) values (
    l.organizacao_id, l.tipo, left('Estorno: ' || l.descricao, 140), -l.valor, current_date, current_date, current_date,
    'efetivado', l.conta_id, l.conta_destino_id, l.categoria_id, 'Motivo do estorno: ' || btrim(p_motivo), 'estorno',
    l.negocio_id, l.pessoa_id, l.contrato_id, l.id
  ) returning * into e;
  perform public.gerar_movimentos(e.id);
  return e;
end;
$$;
revoke all on function public.estornar_lancamento(uuid, text) from public, anon;
grant execute on function public.estornar_lancamento(uuid, text) to authenticated;
