-- =============================================================================
-- 0134 · Avisos de "no dia" e "depois do vencimento" continuam para quem já suspendeu
-- =============================================================================
-- Bug real encontrado pelo proprietário: gerar_notificacoes (0073) exigia
-- c.status = 'ativo' pra TODO aviso — inclusive os pontos de regua_apos (ex.:
-- +1, +3, +5, +15, +30 dias). No Servidor Toptv, com bloqueio_apos_dias = 0,
-- o contrato suspende no dia seguinte ao vencimento — então a régua "avisar
-- depois", que existe justamente pra cobrar quem não pagou, parava de
-- funcionar assim que o contrato era bloqueado. Efeito contrário ao
-- pretendido.
--
-- Correção: só o aviso "antes do vencimento" (proximo_vencimento) continua
-- exigindo contrato ativo — não faz sentido avisar de uma fatura futura de
-- quem já está suspenso. Os avisos "no dia" (vencimento) e "depois"
-- (bloqueio) passam a valer também para contrato suspenso: o cliente deve,
-- está bloqueado, e é exatamente por isso que precisa continuar recebendo o
-- lembrete até pagar. Contrato encerrado nunca entra (não existe mais).
-- =============================================================================

create or replace function public.gerar_notificacoes(p_organizacao uuid, p_data date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare r record; v_tpl text; v_msg text; n int := 0;
begin
  perform set_config('erp.motor', 'on', true);
  for r in
    select l.id as lancamento_id, l.valor, l.data_vencimento, c.id as contrato_id, c.codigo, c.pessoa_id,
           n2.id as negocio_id, n2.nome as negocio, pl.nome as plano, pe.nome as pessoa, pe.telefone,
           pt.tipo as ponto_tipo, pt.dias as ponto_dias,
           cfg.template_vencimento_proximo, cfg.template_vencimento_dia, cfg.template_bloqueio, cfg.provedor
      from public.lancamentos l
      join public.contratos c on c.id = l.contrato_id
      join public.negocios n2 on n2.id = c.negocio_id
      join public.planos pl on pl.id = c.plano_id
      join public.pessoas pe on pe.id = c.pessoa_id
      join public.notificacoes_config cfg on cfg.negocio_id = n2.id
      cross join lateral (
        select 'proximo_vencimento'::public.tipo_notificacao as tipo, d::smallint as dias, (l.data_vencimento - d)::date as dia from unnest(cfg.regua_antes) d
        union all
        select 'vencimento'::public.tipo_notificacao, 0::smallint, l.data_vencimento
        union all
        select 'bloqueio'::public.tipo_notificacao, d::smallint, (l.data_vencimento + d)::date from unnest(cfg.regua_apos) d
      ) pt
     where l.organizacao_id = p_organizacao and l.status = 'previsto' and l.tipo = 'receita' and l.contrato_id is not null
       and n2.ativo and cfg.ativo and pe.receber_avisos
       and (c.status = 'ativo' or (c.status = 'suspenso' and pt.tipo <> 'proximo_vencimento'))
       and pt.dia = p_data
     order by l.data_vencimento, c.codigo
  loop
    -- um aviso por ponto; registros antigos (dias null) valem pelo tipo inteiro
    if exists (select 1 from public.notificacoes_log g where g.lancamento_id = r.lancamento_id and g.tipo = r.ponto_tipo and (g.dias is null or g.dias = r.ponto_dias)) then continue; end if;
    v_tpl := case r.ponto_tipo when 'proximo_vencimento' then r.template_vencimento_proximo when 'vencimento' then r.template_vencimento_dia else r.template_bloqueio end;
    v_msg := public.renderizar_template(v_tpl, jsonb_build_object(
      'nome', r.pessoa, 'negocio', r.negocio, 'plano', r.plano, 'valor', public.moeda_br(r.valor),
      'vencimento', to_char(r.data_vencimento, 'DD/MM/YYYY'), 'contrato', '#' || lpad(r.codigo::text, 3, '0'), 'dias', r.ponto_dias::text));
    insert into public.notificacoes_log (organizacao_id, negocio_id, contrato_id, pessoa_id, lancamento_id, tipo, dias, data_referencia, numero_destino, mensagem, status, provedor, erro)
    values (p_organizacao, r.negocio_id, r.contrato_id, r.pessoa_id, r.lancamento_id, r.ponto_tipo, r.ponto_dias, r.data_vencimento, public.numero_e164(r.telefone), v_msg,
            case when r.telefone is null then 'erro' else 'pendente' end::public.status_notificacao, r.provedor,
            case when r.telefone is null then 'Cliente sem telefone cadastrado.' end);
    n := n + 1;
  end loop;
  return n;
end;
$$;
