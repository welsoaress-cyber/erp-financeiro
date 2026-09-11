-- =============================================================================
-- 0072 · Etapa 47 — Voto de confiança na Cobrança
-- =============================================================================
-- O admin dá um voto de confiança com data ("segura até dia X"): o contrato
-- sai da lista de bloqueio até lá. Se a data passar e a dívida continuar,
-- a confiança vira "furada" e o contrato volta à lista DESTACADO — o admin
-- sabe que já confiou uma vez. Se o cliente pagar dentro do prazo, a
-- confiança é marcada como cumprida. Tudo fica registrado (quem deu, quando,
-- até quando, como terminou) — histórico imutável via auditoria.
-- =============================================================================

create type public.status_confianca as enum ('ativa', 'cumprida', 'furada', 'cancelada');

create table public.confiancas (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  contrato_id uuid not null references public.contratos (id),
  pessoa_id uuid not null references public.pessoas (id),
  segurar_ate date not null,
  observacao text,
  status public.status_confianca not null default 'ativa',
  criado_em timestamptz not null default now(),
  usuario_id uuid,
  resolvido_em timestamptz
);
create unique index confiancas_ativa_unica on public.confiancas (contrato_id) where status = 'ativa';
create index confiancas_negocio on public.confiancas (negocio_id, status);
create trigger confiancas_auditoria after insert or update or delete on public.confiancas for each row execute function public.tg_auditoria();

alter table public.confiancas enable row level security;
create policy confiancas_org on public.confiancas for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.confiancas from public, anon, authenticated;
grant select on public.confiancas to authenticated;

-- destaque na lista de bloqueio: este contrato já furou uma confiança
alter table public.bloqueios add column confianca_furada boolean not null default false;

-- Dar o voto: segura o bloqueio até a data (máx. 90 dias). Substitui confiança
-- ativa anterior e descarta o bloqueio pendente do contrato na hora.
create function public.dar_confianca(p_contrato_id uuid, p_segurar_ate date, p_observacao text default null)
returns public.confiancas
language plpgsql
security definer
set search_path = public
as $$
declare c public.contratos%rowtype; v public.confiancas%rowtype;
begin
  select * into c from public.contratos where id = p_contrato_id;
  if not found then raise exception 'Contrato não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(c.organizacao_id);
  if c.tipo_financeiro <> 'receita' then
    raise exception 'Confiança só vale para contrato de receita.' using errcode = 'check_violation';
  end if;
  if p_segurar_ate is null or p_segurar_ate <= current_date then
    raise exception 'A data precisa ser futura.' using errcode = 'check_violation';
  end if;
  if p_segurar_ate > current_date + 90 then
    raise exception 'Confiança de no máximo 90 dias.' using errcode = 'check_violation';
  end if;
  update public.confiancas set status = 'cancelada', resolvido_em = now()
   where contrato_id = p_contrato_id and status = 'ativa';
  insert into public.confiancas (organizacao_id, negocio_id, contrato_id, pessoa_id, segurar_ate, observacao, usuario_id)
  values (c.organizacao_id, c.negocio_id, p_contrato_id, c.pessoa_id, p_segurar_ate, nullif(trim(p_observacao), ''), auth.uid())
  returning * into v;
  update public.bloqueios set status = 'descartado', executado_em = now(), usuario_id = auth.uid()
   where contrato_id = p_contrato_id and tipo = 'bloqueio' and status = 'pendente';
  return v;
end;
$$;

create function public.cancelar_confianca(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v public.confiancas%rowtype;
begin
  select * into v from public.confiancas where id = p_id;
  if not found then raise exception 'Confiança não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(v.organizacao_id);
  if v.status <> 'ativa' then raise exception 'Confiança já encerrada.' using errcode = 'check_violation'; end if;
  update public.confiancas set status = 'cancelada', resolvido_em = now() where id = p_id;
end;
$$;

revoke all on function public.dar_confianca(uuid, date, text), public.cancelar_confianca(uuid) from public, anon;
grant execute on function public.dar_confianca(uuid, date, text), public.cancelar_confianca(uuid) to authenticated;

-- gerar_bloqueios passa a respeitar a confiança:
--   · resolve as ativas (pagou → cumprida; prazo venceu devendo → furada)
--   · contrato com confiança ativa não entra na lista (pendente é descartado)
--   · última confiança furada → bloqueio volta destacado
create or replace function public.gerar_bloqueios(p_negocio_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; v_dias int; v_blq int := 0; v_dsb int := 0; r record;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(n.organizacao_id);
  select coalesce(max(dias_apos), 3) into v_dias from public.notificacoes_config where negocio_id = p_negocio_id;

  -- confianças ativas: cliente pagou tudo → cumprida; prazo passou devendo → furada
  update public.confiancas v set status = 'cumprida', resolvido_em = now()
   where v.negocio_id = p_negocio_id and v.status = 'ativa'
     and not exists (select 1 from public.lancamentos l where l.contrato_id = v.contrato_id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date);
  update public.confiancas v set status = 'furada', resolvido_em = now()
   where v.negocio_id = p_negocio_id and v.status = 'ativa' and v.segurar_ate < current_date;

  for r in
    select c.id, c.pessoa_id, min(l.data_vencimento) as vencida_desde, count(l.id) as vencidas, sum(l.valor) as total,
           exists (select 1 from public.confiancas v where v.contrato_id = c.id and v.status = 'furada'
                    and v.criado_em > coalesce((select max(v2.criado_em) from public.confiancas v2 where v2.contrato_id = c.id and v2.status = 'cumprida'), '-infinity')) as furou
      from public.contratos c
      join public.lancamentos l on l.contrato_id = c.id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date - v_dias
     where c.negocio_id = p_negocio_id and c.status = 'ativo' and c.tipo_financeiro = 'receita'
       and not exists (select 1 from public.confiancas v where v.contrato_id = c.id and v.status = 'ativa')
     group by c.id, c.pessoa_id
  loop
    insert into public.bloqueios (organizacao_id, negocio_id, contrato_id, pessoa_id, tipo, motivo, confianca_furada)
    values (n.organizacao_id, p_negocio_id, r.id, r.pessoa_id, 'bloqueio',
            r.vencidas || ' cobrança(s) vencida(s) desde ' || to_char(r.vencida_desde, 'DD/MM/YYYY') || ' · R$ ' || to_char(r.total, 'FM999G999G990D00'),
            r.furou)
    on conflict (contrato_id, tipo) where status = 'pendente'
    do update set motivo = excluded.motivo, confianca_furada = excluded.confianca_furada;
    v_blq := v_blq + 1;
  end loop;

  for r in
    select c.id, c.pessoa_id
      from public.contratos c
     where c.negocio_id = p_negocio_id and c.status = 'suspenso' and c.tipo_financeiro = 'receita'
       and not exists (select 1 from public.lancamentos l where l.contrato_id = c.id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date)
  loop
    insert into public.bloqueios (organizacao_id, negocio_id, contrato_id, pessoa_id, tipo, motivo)
    values (n.organizacao_id, p_negocio_id, r.id, r.pessoa_id, 'desbloqueio', 'Pagamentos em dia — liberar o acesso')
    on conflict do nothing;
    v_dsb := v_dsb + 1;
  end loop;

  -- pendências que deixaram de valer somem sozinhas (pagou, ou ganhou confiança)
  update public.bloqueios b set status = 'descartado'
   where b.negocio_id = p_negocio_id and b.status = 'pendente' and b.tipo = 'bloqueio'
     and (not exists (select 1 from public.lancamentos l where l.contrato_id = b.contrato_id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date - v_dias)
          or exists (select 1 from public.confiancas v where v.contrato_id = b.contrato_id and v.status = 'ativa'));
  update public.bloqueios b set status = 'descartado'
   where b.negocio_id = p_negocio_id and b.status = 'pendente' and b.tipo = 'desbloqueio'
     and not exists (select 1 from public.contratos c where c.id = b.contrato_id and c.status = 'suspenso');

  return jsonb_build_object('bloqueios', v_blq, 'desbloqueios', v_dsb);
end;
$$;
