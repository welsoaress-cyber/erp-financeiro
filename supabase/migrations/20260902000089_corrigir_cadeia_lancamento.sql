-- =============================================================================
-- 0089 · Correção de cadastro em parcelamento já gerado
-- =============================================================================
-- Com parcelas geradas, o trigger barra qualquer mudança em conta, categoria,
-- negócio, pessoa e contrato — e a tela deixava o dono editar o campo e
-- descartava em silêncio ao salvar. O motivo da trava é real: mudar só UMA
-- parcela deixa o parcelamento inconsistente.
--
-- A saída não é afrouxar a trava, é corrigir a CADEIA INTEIRA de uma vez:
-- fornecedor, categoria, contrato, negócio e centro de custo de uma compra
-- parcelada são os mesmos em todas as parcelas. corrigir_cadeia_lancamento
-- faz isso sob a flag erp.corrigir_cadeia, que o trigger passa a respeitar.
--
-- Fora do escopo de propósito: conta (mexe em saldo e em fatura de cartão) e
-- os campos da recorrência em si (número de parcelas, periodicidade).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.tg_lancamentos_recorrencia()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_tem_filha boolean;
  o public.lancamentos%rowtype;
begin
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
    elsif new.recorrente and (new.parcela_atual < 1 or (new.numero_parcelas is not null and new.parcela_atual > new.numero_parcelas)) then
      raise exception 'Parcela inicial inválida (use de 1 até o total de parcelas).' using errcode = 'check_violation';
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
    -- corrigir_cadeia_lancamento muda cadastro em TODAS as parcelas de uma vez: aí é coerente
    if coalesce(current_setting('erp.corrigir_cadeia', true), '') <> 'on'
       and ((new.conta_id <> old.conta_id and coalesce(current_setting('erp.trocar_conta', true), '') <> 'on')
         or new.conta_destino_id is distinct from old.conta_destino_id
         or new.categoria_id is distinct from old.categoria_id or new.negocio_id is distinct from old.negocio_id
         or new.pessoa_id is distinct from old.pessoa_id or new.contrato_id is distinct from old.contrato_id) then
      raise exception 'Lançamento com parcelas geradas: corrija o cadastro pela opção "aplicar em todas as parcelas".' using errcode = 'check_violation';
    end if;
    if (new.data_competencia <> old.data_competencia or new.data_vencimento <> old.data_vencimento)
       and coalesce(current_setting('erp.editar_data', true), '') <> 'on' then
      raise exception 'Data de recorrência muda pela edição em lote ("apenas esta" ou "esta e as futuras").' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$function$;

-- Corrige o cadastro em toda a cadeia (raiz + descendentes), pulando canceladas.
-- Conta fica de fora de propósito: mudaria saldo e fatura já fechada.
create or replace function public.corrigir_cadeia_lancamento(
  p_id uuid,
  p_pessoa_id uuid default null,
  p_categoria_id uuid default null,
  p_contrato_id uuid default null,
  p_negocio_id uuid default null,
  p_centro_custo_id uuid default null
)
returns setof public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  v_raiz uuid;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.tipo = 'transferencia' then
    raise exception 'Transferência não tem fornecedor nem categoria.' using errcode = 'check_violation';
  end if;

  -- sobe até a raiz da cadeia e desce por todos os descendentes
  with recursive acima as (
    select * from public.lancamentos where id = p_id
    union all
    select p.* from public.lancamentos p join acima a on p.id = a.lancamento_origem_id
  )
  select id into v_raiz from acima where lancamento_origem_id is null limit 1;
  v_raiz := coalesce(v_raiz, p_id);

  perform set_config('erp.motor', 'on', true);
  perform set_config('erp.corrigir_cadeia', 'on', true);
  return query
  with recursive cadeia as (
    select * from public.lancamentos where id = v_raiz
    union all
    select f.* from public.lancamentos f join cadeia c on f.lancamento_origem_id = c.id
  )
  update public.lancamentos x set
    pessoa_id       = p_pessoa_id,
    categoria_id    = case when x.tipo = 'transferencia' then null else p_categoria_id end,
    contrato_id     = p_contrato_id,
    negocio_id      = p_negocio_id,
    centro_custo_id = p_centro_custo_id
  where x.id in (select id from cadeia) and x.status <> 'cancelado'
  returning x.*;
end;
$$;

revoke all on function public.corrigir_cadeia_lancamento(uuid, uuid, uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.corrigir_cadeia_lancamento(uuid, uuid, uuid, uuid, uuid, uuid) to authenticated;
