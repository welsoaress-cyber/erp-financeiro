-- Etapa 57: bloqueio/desbloqueio automático (opt-in por negócio).
-- Antes disso a régua só SUGERIA quem bloquear/desbloquear (Financeiro →
-- Cobrança) e um humano confirmava com "Bloqueei na rede", porque em geral o
-- ERP não manda comando nenhum pra rede. No caso da Servnet o ReceitaNet já
-- bloqueia e libera o acesso sozinho, pelas próprias regras dele — então aqui
-- só falta o ERP acompanhar isso sem esperar o clique manual. Continua opt-in
-- (`bloqueio_automatico` desligado por padrão): quem não tem esse
-- comportamento automático do lado da rede continua no fluxo assistido.
alter table public.notificacoes_config add column bloqueio_automatico boolean not null default false;
comment on column public.notificacoes_config.bloqueio_automatico is 'Se true, o robô diário confirma bloqueio/desbloqueio sozinho — pressupõe que a rede (ReceitaNet/OLT) já corta e libera o acesso por conta própria, sem depender do clique manual no ERP.';

alter table public.bloqueios add column automatico boolean not null default false;
comment on column public.bloqueios.automatico is 'true = confirmado pelo robô diário (bloqueio_automatico ligado no negócio); false = admin clicou manualmente em "Bloqueei/Desbloqueei na rede".';

-- Espelho interno de gerar_bloqueios (0072/0059), sem exigir_membro — só o robô chama.
-- Mesma lógica; se gerar_bloqueios mudar, replicar aqui.
create function public.gerar_bloqueios_interno(p_negocio_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; v_dias int; r record;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then return; end if;
  select coalesce(max(dias_apos), 3) into v_dias from public.notificacoes_config where negocio_id = p_negocio_id;

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

-- Confirma um pendente sem sessão de usuário: usuario_id fica null, automatico=true.
create function public.executar_bloqueio_interno(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare b public.bloqueios%rowtype;
begin
  select * into b from public.bloqueios where id = p_id and status = 'pendente';
  if not found then return; end if;
  update public.bloqueios set status = 'executado', executado_em = now(), automatico = true where id = p_id;
  update public.contratos set status = case when b.tipo = 'bloqueio' then 'suspenso' else 'ativo' end::public.status_contrato
   where id = b.contrato_id and status = case when b.tipo = 'bloqueio' then 'ativo' else 'suspenso' end::public.status_contrato;
end;
$$;
revoke all on function public.executar_bloqueio_interno(uuid) from public, anon, authenticated;

-- Robô diário: só mexe nos negócios com bloqueio_automatico ligado (opt-in).
create function public.executar_bloqueios_automaticos()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_neg record; v_item record; v_total int := 0;
begin
  for v_neg in select negocio_id from public.notificacoes_config where bloqueio_automatico loop
    perform public.gerar_bloqueios_interno(v_neg.negocio_id);
    for v_item in select id from public.bloqueios where negocio_id = v_neg.negocio_id and status = 'pendente' loop
      perform public.executar_bloqueio_interno(v_item.id);
      v_total := v_total + 1;
    end loop;
  end loop;
  return jsonb_build_object('executados', v_total);
end;
$$;
revoke all on function public.executar_bloqueios_automaticos() from public, anon, authenticated;
grant execute on function public.executar_bloqueios_automaticos() to service_role; -- pg_cron roda como postgres (bypassa tudo); o grant é só defesa/teste

-- Relatório: bloqueios/desbloqueios executados, manual × automático.
create view public.vw_rel_bloqueios with (security_invoker = true) as
select b.id, b.organizacao_id, b.negocio_id, n.nome as negocio, p.nome as cliente,
       (case b.tipo when 'bloqueio' then 'Bloqueio' else 'Desbloqueio' end) as tipo,
       (case b.status when 'pendente' then 'Pendente' when 'executado' then 'Executado' else 'Descartado' end) as status,
       (case when b.automatico then 'Automático' else 'Manual' end) as automatico,
       b.motivo, b.criado_em, b.executado_em
  from public.bloqueios b
  join public.negocios n on n.id = b.negocio_id
  join public.pessoas p on p.id = b.pessoa_id;
grant select on public.vw_rel_bloqueios to authenticated;
