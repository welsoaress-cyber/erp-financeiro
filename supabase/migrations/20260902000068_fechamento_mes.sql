-- =============================================================================
-- 0068 · Etapa 42 — Fechamento de mês (trava contra alteração retroativa)
-- =============================================================================
-- Mês fechado = REALIZADO conferido com o banco. A trava protege o caixa do
-- mês: nenhum lançamento efetivado dentro dele pode ser alterado, cancelado
-- ou excluído, e nada novo pode ser efetivado com data dentro dele.
-- Previstos (cobranças em aberto) continuam vivos: podem ser baixados depois
-- (o caixa entra no mês atual) e o faturamento retroativo não quebra.
-- Reabrir é explícito e auditado.
-- =============================================================================

create table public.fechamentos_mes (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  fechado_em timestamptz not null default now(),
  usuario_id uuid,
  unique (organizacao_id, competencia)
);
alter table public.fechamentos_mes enable row level security;
create policy fechamentos_select on public.fechamentos_mes for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.fechamentos_mes from anon;
revoke insert, update, delete on public.fechamentos_mes from authenticated;
create trigger fechamentos_auditoria after insert or delete on public.fechamentos_mes
  for each row execute function public.tg_auditoria();

create function public.mes_fechado(p_organizacao uuid, p_data date)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (select 1 from public.fechamentos_mes
                  where organizacao_id = p_organizacao
                    and competencia = date_trunc('month', p_data)::date);
$$;

create function public.fechar_mes(p_competencia date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid; v_comp date := date_trunc('month', p_competencia)::date;
begin
  select organizacao_id into v_org from public.organizacao_membros where usuario_id = auth.uid() limit 1;
  perform public.exigir_membro(v_org);
  if v_comp >= date_trunc('month', current_date)::date then
    raise exception 'Só é possível fechar meses já encerrados no calendário.' using errcode = 'check_violation';
  end if;
  insert into public.fechamentos_mes (organizacao_id, competencia, usuario_id)
  values (v_org, v_comp, auth.uid())
  on conflict (organizacao_id, competencia) do nothing;
end;
$$;

create function public.reabrir_mes(p_competencia date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid;
begin
  select organizacao_id into v_org from public.organizacao_membros where usuario_id = auth.uid() limit 1;
  perform public.exigir_membro(v_org);
  delete from public.fechamentos_mes
   where organizacao_id = v_org and competencia = date_trunc('month', p_competencia)::date;
end;
$$;
revoke all on function public.fechar_mes(date), public.reabrir_mes(date), public.mes_fechado(uuid, date) from public, anon;
grant execute on function public.fechar_mes(date), public.reabrir_mes(date), public.mes_fechado(uuid, date) to authenticated;

-- trava nos lançamentos: o realizado de mês fechado é intocável
create function public.tg_lancamentos_fechamento()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if old.data_efetivacao is not null and public.mes_fechado(old.organizacao_id, old.data_efetivacao) then
      raise exception 'Mês % está fechado — lançamento efetivado nele não pode ser excluído; reabra o mês.', to_char(old.data_efetivacao, 'MM/YYYY') using errcode = 'check_violation';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and old.data_efetivacao is not null and old.status = 'efetivado'
     and public.mes_fechado(old.organizacao_id, old.data_efetivacao) then
    raise exception 'Mês % está fechado — lançamento efetivado nele não pode ser alterado; reabra o mês.', to_char(old.data_efetivacao, 'MM/YYYY') using errcode = 'check_violation';
  end if;
  -- nada novo pode ser efetivado com data dentro de mês fechado
  if new.data_efetivacao is not null and (tg_op = 'INSERT' or new.data_efetivacao is distinct from old.data_efetivacao)
     and public.mes_fechado(new.organizacao_id, new.data_efetivacao) then
    raise exception 'Mês % está fechado — use uma data de efetivação em mês aberto.', to_char(new.data_efetivacao, 'MM/YYYY') using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger lancamentos_a0_fechamento before insert or update or delete on public.lancamentos
  for each row execute function public.tg_lancamentos_fechamento();
