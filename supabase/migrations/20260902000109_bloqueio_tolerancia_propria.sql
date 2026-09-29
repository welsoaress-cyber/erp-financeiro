-- Pedido do proprietário: tolerância zero — "venceu, bloqueou", sem esperar dias extras.
-- Hoje o prazo do bloqueio (gerar_bloqueios/gerar_bloqueios_interno) usa notificacoes_config.dias_apos
-- — o MESMO campo que define o último ponto da régua de avisos por WhatsApp (regua_apos, 0073),
-- que por sua vez não aceita 0 (um aviso "0 dias depois do vencimento" coincidiria com o aviso "vence
-- hoje" e não faz sentido como régua de mensagem). Separar os dois em vez de forçar 0 num campo que
-- não foi desenhado pra isso: prazo do bloqueio ganha campo próprio, sem acoplamento com a régua de
-- avisos — cada negócio pode ter mensagens de aviso em X dias e ainda assim bloquear no dia seguinte
-- ao vencimento (0 = sem tolerância extra; a checagem já roda a partir do dia seguinte, no cron das
-- 00:00 ou no botão manual).
alter table public.notificacoes_config
  add column bloqueio_apos_dias smallint not null default 3 check (bloqueio_apos_dias between 0 and 60);
comment on column public.notificacoes_config.bloqueio_apos_dias is 'Dias após o vencimento pra considerar a cobrança bloqueável (0 = bloqueia assim que vence, sem tolerância extra). Independente da régua de avisos por WhatsApp (regua_apos).';
-- preserva o comportamento atual de cada negócio (era dias_apos) até o proprietário decidir mudar
update public.notificacoes_config set bloqueio_apos_dias = dias_apos;

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
     where c.negocio_id = p_negocio_id and c.status = 'suspenso' and c.tipo_financeiro = 'receita'
       and not exists (select 1 from public.lancamentos l where l.contrato_id = c.id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date)
  loop
    insert into public.bloqueios (organizacao_id, negocio_id, contrato_id, pessoa_id, tipo, motivo)
    values (n.organizacao_id, p_negocio_id, r.id, r.pessoa_id, 'desbloqueio', 'Pagamentos em dia — liberar o acesso')
    on conflict do nothing;
  end loop;

  update public.bloqueios b set status = 'descartado'
   where b.negocio_id = p_negocio_id and b.status = 'pendente' and b.tipo = 'bloqueio'
     and (not exists (select 1 from public.lancamentos l where l.contrato_id = b.contrato_id and l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date - v_dias)
          or exists (select 1 from public.confiancas v where v.contrato_id = b.contrato_id and v.status = 'ativa'));
  update public.bloqueios b set status = 'descartado'
   where b.negocio_id = p_negocio_id and b.status = 'pendente' and b.tipo = 'desbloqueio'
     and not exists (select 1 from public.contratos c where c.id = b.contrato_id and c.status = 'suspenso');
end;
$$;
revoke all on function public.gerar_bloqueios_interno(uuid) from public, anon, authenticated;
