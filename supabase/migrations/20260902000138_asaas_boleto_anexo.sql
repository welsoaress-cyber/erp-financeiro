-- =============================================================================
-- 0138 · Boleto Asaas anexado no aviso de WhatsApp (Servnet)
-- =============================================================================
-- O ReceitaNet já gera a cobrança (boleto/Pix) direto na conta Asaas do
-- proprietário. Nada aqui cria cobrança nova — só busca a cobrança que já
-- existe no Asaas (casando pelo CPF do cliente) e anexa o PDF do boleto na
-- mensagem de cobrança que a régua já envia. Opt-in por negócio
-- (notificacoes_config.asaas_ativo) — só Servnet liga.
--
-- notificacoes_para_envio passa a devolver também o CPF da pessoa e o
-- valor/vencimento do lançamento, pra Edge Function casar com a cobrança
-- certa no Asaas (mesmo CPF + mesmo valor + mesmo vencimento).
-- =============================================================================

alter table public.notificacoes_config add column asaas_ativo boolean not null default false;
comment on column public.notificacoes_config.asaas_ativo is 'Liga a busca da cobrança no Asaas (por CPF) pra anexar o PDF do boleto no aviso de WhatsApp. Opt-in — hoje só Servnet.';

drop function public.notificacoes_para_envio(integer);
create function public.notificacoes_para_envio(p_limite integer default 50)
returns table (
  id uuid, negocio_id uuid, instancia text, numero_destino text, mensagem text, tipo public.tipo_notificacao, tentativas smallint,
  asaas_ativo boolean, documento text, lanc_valor numeric, lanc_vencimento date
)
language plpgsql
security definer
set search_path = public
as $$
declare v_hora time := (now() at time zone 'America/Sao_Paulo')::time;
begin
  perform set_config('erp.motor', 'on', true);
  update public.notificacoes_log g set status = 'erro', erro = 'Cobrança já paga ou cancelada antes do envio.'
   where g.status = 'pendente' and g.lancamento_id is not null
     and exists (select 1 from public.lancamentos l where l.id = g.lancamento_id and l.status <> 'previsto');
  update public.notificacoes_log g set status = 'erro', erro = 'Vencimento foi alterado depois deste aviso ter sido gerado — não é mais "antes do vencimento".'
   where g.status = 'pendente' and g.tipo = 'proximo_vencimento'
     and exists (select 1 from public.lancamentos l where l.id = g.lancamento_id and l.status = 'previsto' and l.data_vencimento <= current_date);

  return query
    select g.id, g.negocio_id, cfg.instancia,
           coalesce(public.numero_e164(pe.telefone), g.numero_destino) as numero_destino,
           case when g.lancamento_id is null then g.mensagem
                else public.renderizar_template(
                  case g.tipo when 'proximo_vencimento' then cfg.template_vencimento_proximo when 'vencimento' then cfg.template_vencimento_dia else cfg.template_bloqueio end,
                  jsonb_build_object('nome', pe.nome, 'negocio', n.nome, 'plano', pl.nome, 'valor', public.moeda_br(l.valor),
                                      'vencimento', to_char(l.data_vencimento, 'DD/MM/YYYY'), 'contrato', '#' || lpad(c.codigo::text, 3, '0'), 'dias', g.dias::text))
           end as mensagem,
           g.tipo, g.tentativas,
           cfg.asaas_ativo, pe.documento, l.valor, l.data_vencimento
      from public.notificacoes_log g
      join public.notificacoes_config cfg on cfg.negocio_id = g.negocio_id
      join public.negocios n on n.id = g.negocio_id
      join public.pessoas pe on pe.id = g.pessoa_id
      left join public.lancamentos l on l.id = g.lancamento_id
      left join public.contratos c on c.id = l.contrato_id
      left join public.planos pl on pl.id = c.plano_id
     where g.status = 'pendente' and coalesce(public.numero_e164(pe.telefone), g.numero_destino) is not null and cfg.ativo and n.ativo
       and cfg.provedor::text = 'evolution' and cfg.instancia is not null
       and v_hora >= cfg.hora_inicio and v_hora < cfg.hora_fim
       and g.tentativas < 5
     order by g.criado_em
     limit p_limite;
end;
$$;
revoke all on function public.notificacoes_para_envio(integer) from public, anon, authenticated;
grant execute on function public.notificacoes_para_envio(integer) to service_role;
