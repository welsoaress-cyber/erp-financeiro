-- =============================================================================
-- 0121 · Bloqueio por pessoa, não só pelo contrato isolado
-- =============================================================================
-- Caso real: mesma pessoa, mesmo negócio (Servidor Toptv), três contratos
-- (#029 e #069 suspensos por inadimplência, #085 novo e "limpo"). O motor de
-- bloqueio olhava cada contrato isoladamente: #085 não tinha nada vencido
-- NELE MESMO, então ficava "Ativo" — mesmo a pessoa devendo em outro
-- contrato dela. Regra do proprietário (agora em CLAUDE.md, regra
-- inegociável): cliente inadimplente perde acesso a tudo, sem exceção —
-- sempre checar por pessoa, nunca só pelo contrato isolado. Mesmo padrão já
-- usado na 0114 (curso cortesia segue a inadimplência dos outros contratos).
--
-- `gerar_bloqueios`/`gerar_bloqueios_interno` ganham um segundo motivo de
-- bloqueio: contrato ativo cuja pessoa tem OUTRO contrato de receita
-- suspenso (qualquer negócio da organização — mesmo critério cross-negócio
-- da 0114). O desbloqueio (e o descarte de bloqueio pendente que deixou de
-- valer) passam a exigir também que nenhum contrato irmão continue
-- suspenso, senão a pessoa voltaria a ter acesso em um contrato ainda com
-- outro suspenso.
-- =============================================================================

create function public.pessoa_tem_contrato_suspenso(p_pessoa_id uuid, p_excluir_contrato_id uuid)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1 from public.contratos c2
     where c2.pessoa_id = p_pessoa_id and c2.id <> p_excluir_contrato_id
       and c2.tipo_financeiro = 'receita' and c2.status = 'suspenso'
  )
$$;
revoke all on function public.pessoa_tem_contrato_suspenso(uuid, uuid) from public, anon, authenticated;

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
  select coalesce(max(bloqueio_apos_dias), 3) into v_dias from public.notificacoes_config where negocio_id = p_negocio_id;

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

  -- dívida em OUTRO contrato de receita da mesma pessoa (contrato recriado em vez de
  -- reativado: a dívida antiga não pode ficar invisível porque o novo, isolado, está em dia)
  for r in
    select c.id, c.pessoa_id
      from public.contratos c
     where c.negocio_id = p_negocio_id and c.status = 'ativo' and c.tipo_financeiro = 'receita'
       and not exists (select 1 from public.confiancas v where v.contrato_id = c.id and v.status = 'ativa')
       and public.pessoa_tem_contrato_suspenso(c.pessoa_id, c.id)
  loop
    insert into public.bloqueios (organizacao_id, negocio_id, contrato_id, pessoa_id, tipo, motivo)
    values (n.organizacao_id, p_negocio_id, r.id, r.pessoa_id, 'bloqueio', 'Mesma pessoa com outro contrato suspenso por inadimplência.')
    on conflict (contrato_id, tipo) where status = 'pendente'
    do update set motivo = excluded.motivo;
    v_blq := v_blq + 1;
  end loop;

  for r in
    select c.id, c.pessoa_id
      from public.contratos c
     where c.negocio_id = p_negocio_id and c.status = 'suspenso' and c.tipo_financeiro = 'receita'
       and not exists (select 1 from public.lancamentos l where l.contrato_id = c.id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date)
       and not public.pessoa_tem_contrato_suspenso(c.pessoa_id, c.id)
  loop
    insert into public.bloqueios (organizacao_id, negocio_id, contrato_id, pessoa_id, tipo, motivo)
    values (n.organizacao_id, p_negocio_id, r.id, r.pessoa_id, 'desbloqueio', 'Pagamentos em dia — liberar o acesso')
    on conflict do nothing;
    v_dsb := v_dsb + 1;
  end loop;

  -- pendências que deixaram de valer somem sozinhas (pagou, ganhou confiança, ou o
  -- contrato irmão que motivava o bloqueio cruzado deixou de estar suspenso)
  update public.bloqueios b set status = 'descartado'
   where b.negocio_id = p_negocio_id and b.status = 'pendente' and b.tipo = 'bloqueio'
     and not exists (select 1 from public.lancamentos l where l.contrato_id = b.contrato_id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date - v_dias)
     and not public.pessoa_tem_contrato_suspenso((select pessoa_id from public.contratos where id = b.contrato_id), b.contrato_id)
     and not exists (select 1 from public.confiancas v where v.contrato_id = b.contrato_id and v.status = 'ativa');
  update public.bloqueios b set status = 'descartado'
   where b.negocio_id = p_negocio_id and b.status = 'pendente' and b.tipo = 'desbloqueio'
     and not exists (select 1 from public.contratos c where c.id = b.contrato_id and c.status = 'suspenso');

  return jsonb_build_object('bloqueios', v_blq, 'desbloqueios', v_dsb);
end;
$$;

create or replace function public.gerar_bloqueios_interno(p_negocio_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; v_dias int; r record;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then return; end if;
  select coalesce(max(bloqueio_apos_dias), 3) into v_dias from public.notificacoes_config where negocio_id = p_negocio_id;

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
  end loop;

  for r in
    select c.id, c.pessoa_id
      from public.contratos c
     where c.negocio_id = p_negocio_id and c.status = 'ativo' and c.tipo_financeiro = 'receita'
       and not exists (select 1 from public.confiancas v where v.contrato_id = c.id and v.status = 'ativa')
       and public.pessoa_tem_contrato_suspenso(c.pessoa_id, c.id)
  loop
    insert into public.bloqueios (organizacao_id, negocio_id, contrato_id, pessoa_id, tipo, motivo)
    values (n.organizacao_id, p_negocio_id, r.id, r.pessoa_id, 'bloqueio', 'Mesma pessoa com outro contrato suspenso por inadimplência.')
    on conflict (contrato_id, tipo) where status = 'pendente'
    do update set motivo = excluded.motivo;
  end loop;

  for r in
    select c.id, c.pessoa_id
      from public.contratos c
     where c.negocio_id = p_negocio_id and c.status = 'suspenso' and c.tipo_financeiro = 'receita'
       and not exists (select 1 from public.lancamentos l where l.contrato_id = c.id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date)
       and not public.pessoa_tem_contrato_suspenso(c.pessoa_id, c.id)
  loop
    insert into public.bloqueios (organizacao_id, negocio_id, contrato_id, pessoa_id, tipo, motivo)
    values (n.organizacao_id, p_negocio_id, r.id, r.pessoa_id, 'desbloqueio', 'Pagamentos em dia — liberar o acesso')
    on conflict do nothing;
  end loop;

  update public.bloqueios b set status = 'descartado'
   where b.negocio_id = p_negocio_id and b.status = 'pendente' and b.tipo = 'bloqueio'
     and not exists (select 1 from public.lancamentos l where l.contrato_id = b.contrato_id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date - v_dias)
     and not public.pessoa_tem_contrato_suspenso((select pessoa_id from public.contratos where id = b.contrato_id), b.contrato_id)
     and not exists (select 1 from public.confiancas v where v.contrato_id = b.contrato_id and v.status = 'ativa');
  update public.bloqueios b set status = 'descartado'
   where b.negocio_id = p_negocio_id and b.status = 'pendente' and b.tipo = 'desbloqueio'
     and not exists (select 1 from public.contratos c where c.id = b.contrato_id and c.status = 'suspenso');
end;
$$;
revoke all on function public.gerar_bloqueios_interno(uuid) from public, anon, authenticated;
