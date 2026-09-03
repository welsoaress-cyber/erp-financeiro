-- =============================================================================
-- 0025 · Recorrência: separa "despesa fixa" (repete até cancelar) de "parcelamento" (N parcelas)
-- =============================================================================
-- Etapa 12. Regras aprovadas:
--   avulso     → não se repete (recorrente = false).
--   fixa       → recorrente, sem número de parcelas; ao efetivar gera o próximo mês; só para com cancelamento.
--   parcelada  → recorrente com N parcelas; ao efetivar gera a próxima; para na parcela N.
-- tipo_recorrencia é derivado pelo trigger (fixa ⇔ numero_parcelas nulo), então criar/atualizar_lancamento
-- mantêm a assinatura de 17 parâmetros. Com parcelas geradas, descrição, observação E valor podem mudar.
-- =============================================================================
create type public.tipo_recorrencia as enum ('fixa', 'parcelada');
alter table public.lancamentos add column tipo_recorrencia public.tipo_recorrencia;

-- migração dos dados existentes (sem passar pelos triggers de proteção)
alter table public.lancamentos disable trigger user;
update public.lancamentos set tipo_recorrencia = case when numero_parcelas is null then 'fixa' else 'parcelada' end::public.tipo_recorrencia where recorrente;
alter table public.lancamentos enable trigger user;

alter table public.lancamentos drop constraint lancamentos_recorrencia_check;
alter table public.lancamentos add constraint lancamentos_recorrencia_check check (
  (not recorrente and tipo_recorrencia is null and periodicidade is null and numero_parcelas is null and parcela_atual is null
     and data_fim_recorrencia is null and lancamento_origem_id is null)
  or
  (recorrente and tipo_recorrencia is not null and periodicidade is not null and parcela_atual >= 1
     and ((tipo_recorrencia = 'fixa' and numero_parcelas is null)
       or (tipo_recorrencia = 'parcelada' and numero_parcelas is not null and parcela_atual <= numero_parcelas)))
);

create or replace function public.tg_lancamentos_recorrencia()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_tem_filha boolean;
  o public.lancamentos%rowtype;
begin
  -- tipo derivado: fixa (sem parcelas) ou parcelada
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
    elsif new.recorrente and new.parcela_atual <> 1 then
      raise exception 'A primeira parcela deve ser a de número 1.' using errcode = 'check_violation';
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
    if new.data_competencia <> old.data_competencia or new.data_vencimento <> old.data_vencimento
       or new.conta_id <> old.conta_id or new.conta_destino_id is distinct from old.conta_destino_id
       or new.categoria_id is distinct from old.categoria_id or new.negocio_id is distinct from old.negocio_id
       or new.pessoa_id is distinct from old.pessoa_id or new.contrato_id is distinct from old.contrato_id then
      raise exception 'Lançamento com parcelas geradas: só descrição, valor e observação podem ser alterados.' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;
