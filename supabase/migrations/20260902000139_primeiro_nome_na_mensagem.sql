-- =============================================================================
-- 0139 · {nome} na mensagem de cobrança vira só o primeiro nome
-- =============================================================================
-- Pedido do proprietário: "Olá WELLINGTON SOARES DE SOUZA" é formal demais —
-- o padrão que os clientes já conheciam era "Olá ALEX" (só o primeiro nome).
-- Só muda o que o placeholder {nome} resolve nas 3 funções que montam a
-- mensagem (geração da régua, releitura na hora de enviar, teste manual);
-- o nome completo continua gravado em pessoas.nome normalmente.
-- =============================================================================

create or replace function public.primeiro_nome(p_nome text)
returns text
language sql
immutable
set search_path = public
as $$ select split_part(btrim(coalesce(p_nome, '')), ' ', 1); $$;
comment on function public.primeiro_nome(text) is 'Primeiro nome de uma pessoa, pro {nome} da mensagem de cobrança soar menos formal.';

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
      'nome', public.primeiro_nome(r.pessoa), 'negocio', r.negocio, 'plano', r.plano, 'valor', public.moeda_br(r.valor),
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

create or replace function public.notificacoes_para_envio(p_limite integer default 50)
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
                  jsonb_build_object('nome', public.primeiro_nome(pe.nome), 'negocio', n.nome, 'plano', pl.nome, 'valor', public.moeda_br(l.valor),
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

create or replace function public.enviar_notificacao_teste(p_negocio_id uuid, p_pessoa_id uuid, p_tipo text default 'vencimento')
returns public.notificacoes_log
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; pe public.pessoas%rowtype; cfg public.notificacoes_config%rowtype; v_tpl text; v_msg text; g public.notificacoes_log%rowtype;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio inválido.' using errcode = 'check_violation'; end if;
  perform public.exigir_membro(n.organizacao_id);
  select * into cfg from public.notificacoes_config where negocio_id = p_negocio_id;
  if not found then raise exception 'Configure as notificações do negócio antes de testar.' using errcode = 'check_violation'; end if;
  select * into pe from public.pessoas where id = p_pessoa_id;
  if not found or pe.organizacao_id <> n.organizacao_id then raise exception 'Pessoa inválida.' using errcode = 'check_violation'; end if;
  if pe.telefone is null then raise exception 'A pessoa não tem telefone cadastrado.' using errcode = 'check_violation'; end if;
  v_tpl := case p_tipo when 'proximo_vencimento' then cfg.template_vencimento_proximo when 'bloqueio' then cfg.template_bloqueio else cfg.template_vencimento_dia end;
  v_msg := public.renderizar_template(v_tpl, jsonb_build_object('nome', public.primeiro_nome(pe.nome), 'negocio', n.nome, 'plano', 'Plano exemplo', 'valor', public.moeda_br(99.90),
            'vencimento', to_char(current_date, 'DD/MM/YYYY'), 'contrato', '#000', 'dias', cfg.dias_antes::text));
  perform set_config('erp.motor', 'on', true);
  insert into public.notificacoes_log (organizacao_id, negocio_id, pessoa_id, tipo, data_referencia, numero_destino, mensagem, status, provedor, data_envio)
  values (n.organizacao_id, p_negocio_id, p_pessoa_id, 'teste', current_date, public.numero_e164(pe.telefone), '[TESTE] ' || v_msg,
          case when cfg.provedor::text = 'simulado' then 'simulado' else 'pendente' end::public.status_notificacao, cfg.provedor,
          case when cfg.provedor::text = 'simulado' then now() end)
  returning * into g;
  return g;
end;
$$;
