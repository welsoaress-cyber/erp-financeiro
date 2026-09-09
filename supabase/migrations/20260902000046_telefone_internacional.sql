-- =============================================================================
-- 0046 · Telefone internacional (com "+" e código do país)
-- =============================================================================
-- Número americano cadastrado como 16893162446 (11 dígitos) ganhava +55 na
-- frente e virava um número brasileiro errado. Convenção: internacional se
-- cadastra COM o "+" (ex.: +16893162446); sem "+", continua sendo brasileiro
-- com DDD. numero_e164 respeita o "+" e o check de pessoas passa a aceitá-lo.
-- =============================================================================

alter table public.pessoas drop constraint pessoas_telefone_check;
alter table public.pessoas add constraint pessoas_telefone_check
  check (telefone is null or telefone ~ '^[0-9]{10,13}$' or telefone ~ '^\+[0-9]{8,15}$');

-- o trigger de pessoas removia o "+" na normalização; agora preserva quando é o 1º caractere
-- (mesma versão da 0015, mudando só a linha do telefone)
create or replace function public.tg_pessoas_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.nome := btrim(new.nome);
  new.email := nullif(lower(btrim(coalesce(new.email, ''))), '');
  new.documento := nullif(regexp_replace(coalesce(new.documento, ''), '[^0-9]', '', 'g'), '');
  new.telefone := nullif(
    (case when btrim(coalesce(new.telefone, '')) like '+%' then '+' else '' end) ||
    regexp_replace(coalesce(new.telefone, ''), '[^0-9]', '', 'g'), '');
  if tg_op = 'UPDATE' then
    if new.organizacao_id <> old.organizacao_id then
      raise exception 'A pessoa não pode mudar de organização.' using errcode = 'check_violation';
    end if;
    if old.ativo and not new.ativo then
      if exists (select 1 from public.contratos c where c.pessoa_id = old.id and c.status <> 'encerrado') then
        raise exception 'A pessoa não pode ser inativada: possui contratos vigentes.' using errcode = 'check_violation';
      end if;
      if exists (select 1 from public.pessoa_negocio_vinculos v where v.pessoa_id = old.id and v.ativo) then
        raise exception 'A pessoa não pode ser inativada: possui vínculos ativos com negócios.' using errcode = 'check_violation';
      end if;
      if exists (select 1 from public.lancamentos l where l.pessoa_id = old.id and l.status = 'previsto') then
        raise exception 'A pessoa não pode ser inativada: possui lançamentos previstos pendentes.' using errcode = 'check_violation';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.numero_e164(p_telefone text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_telefone is null then null
    when p_telefone like '+%' then p_telefone
    when char_length(p_telefone) between 10 and 11 then '+55' || p_telefone
    else '+' || p_telefone end;
$$;
