-- =============================================================================
-- 0135 · Envio relê os dados atuais antes de mandar (não usa o que ficou gravado)
-- =============================================================================
-- Caso real: aviso gerado quando a fatura vencia em 10/10; o vencimento foi
-- editado depois pra 07/10 (corrigindo pra "já vencida"); o aviso antigo
-- ficou pendente com a mensagem e a data velhas ("vence em 10/10"), prestes
-- a sair errado. notificacoes_para_envio (chamada pela Edge Function logo
-- antes de enviar) agora relê valor/vencimento do lançamento e telefone da
-- pessoa NA HORA, reconstruindo a mensagem — nunca manda o texto gravado na
-- geração. Dois efeitos:
--   - corrige sozinho o número de telefone se foi atualizado no cadastro
--     depois do aviso gerado (sem precisar de UPDATE manual);
--   - se o aviso é "próximo ao vencimento" mas o vencimento atual já passou
--     (editado pra data anterior), vira erro em vez de sair com data errada
--     — o ponto "bloqueio" correspondente, se existir, continua normal.
-- Avisos de teste (sem lancamento_id) continuam como estão, sem dado pra reler.
-- =============================================================================

create or replace function public.notificacoes_para_envio(p_limite integer default 50)
returns table (id uuid, negocio_id uuid, instancia text, numero_destino text, mensagem text, tipo public.tipo_notificacao, tentativas smallint)
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
           g.tipo, g.tentativas
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
