-- =============================================================================
-- Migration 0018: PROVEDOR "EVOLUTION API" PARA NOTIFICAÇÕES (envio real, opcional)
-- Mesmo caminho do sistema anterior: Evolution API auto-hospedada (VM Oracle
-- Cloud, gratuita), uma instância por negócio. O banco só enfileira; uma Edge
-- Function (supabase/functions/notificacoes-enviar) lê a fila, envia e grava o
-- resultado. Segredos (URL/chave da Evolution) ficam só nos secrets da função.
-- Por padrão todo negócio continua em "simulado": nada é enviado até o
-- proprietário trocar o provedor na tela e configurar os secrets.
-- =============================================================================
alter type public.provedor_notificacao add value if not exists 'evolution';

alter table public.notificacoes_config add column instancia text check (instancia is null or instancia ~ '^[a-z0-9_-]{2,40}$');
comment on column public.notificacoes_config.instancia is 'Nome da instância na Evolution API (ex.: servnet, servidor). Obrigatório no provedor evolution.';

alter table public.notificacoes_log add column resposta_provedor jsonb;
alter table public.notificacoes_log add column tentativas smallint not null default 0;

-- Opt-out por pessoa (equivalente ao "receberLembretes" do sistema anterior)
alter table public.pessoas add column receber_avisos boolean not null default true;
comment on column public.pessoas.receber_avisos is 'false = não recebe avisos de cobrança por WhatsApp.';

-- Config: instância obrigatória quando o provedor exige
create or replace function public.tg_notificacoes_config_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and (new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id) then
    raise exception 'A configuração não pode mudar de negócio.' using errcode = 'check_violation';
  end if;
  perform public.validar_negocio(new.negocio_id, new.organizacao_id, tg_op = 'INSERT');
  new.numero_whatsapp := nullif(regexp_replace(coalesce(new.numero_whatsapp, ''), '[^0-9+]', '', 'g'), '');
  new.instancia := nullif(lower(btrim(coalesce(new.instancia, ''))), '');
  if new.provedor::text = 'evolution' and new.instancia is null then
    raise exception 'Informe o nome da instância da Evolution API para este negócio.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- Geração: respeita o opt-out da pessoa
create or replace function public.gerar_notificacoes(p_organizacao uuid, p_data date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare r record; v_tipo public.tipo_notificacao; v_tpl text; v_msg text; v_dias int; n int := 0;
begin
  perform set_config('erp.motor', 'on', true);
  for r in
    select l.id as lancamento_id, l.valor, l.data_vencimento, c.id as contrato_id, c.codigo, c.pessoa_id,
           n.id as negocio_id, n.nome as negocio, pl.nome as plano, pe.nome as pessoa, pe.telefone,
           cfg.dias_antes, cfg.dias_apos, cfg.template_vencimento_proximo, cfg.template_vencimento_dia, cfg.template_bloqueio, cfg.provedor
      from public.lancamentos l
      join public.contratos c on c.id = l.contrato_id
      join public.negocios n on n.id = c.negocio_id
      join public.planos pl on pl.id = c.plano_id
      join public.pessoas pe on pe.id = c.pessoa_id
      join public.notificacoes_config cfg on cfg.negocio_id = n.id
     where l.organizacao_id = p_organizacao and l.status = 'previsto' and l.tipo = 'receita' and l.contrato_id is not null
       and c.status = 'ativo' and n.ativo and cfg.ativo and pe.receber_avisos
       and p_data in (l.data_vencimento - cfg.dias_antes, l.data_vencimento, l.data_vencimento + cfg.dias_apos)
     order by l.data_vencimento, c.codigo
  loop
    if p_data = r.data_vencimento - r.dias_antes and r.dias_antes > 0 then v_tipo := 'proximo_vencimento'; v_tpl := r.template_vencimento_proximo; v_dias := r.dias_antes;
    elsif p_data = r.data_vencimento then v_tipo := 'vencimento'; v_tpl := r.template_vencimento_dia; v_dias := 0;
    elsif p_data = r.data_vencimento + r.dias_apos then v_tipo := 'bloqueio'; v_tpl := r.template_bloqueio; v_dias := r.dias_apos;
    else continue; end if;
    if exists (select 1 from public.notificacoes_log g where g.lancamento_id = r.lancamento_id and g.tipo = v_tipo) then continue; end if;
    v_msg := public.renderizar_template(v_tpl, jsonb_build_object(
      'nome', r.pessoa, 'negocio', r.negocio, 'plano', r.plano, 'valor', public.moeda_br(r.valor),
      'vencimento', to_char(r.data_vencimento, 'DD/MM/YYYY'), 'contrato', '#' || lpad(r.codigo::text, 3, '0'), 'dias', v_dias::text));
    insert into public.notificacoes_log (organizacao_id, negocio_id, contrato_id, pessoa_id, lancamento_id, tipo, data_referencia, numero_destino, mensagem, status, provedor, erro)
    values (p_organizacao, r.negocio_id, r.contrato_id, r.pessoa_id, r.lancamento_id, v_tipo, r.data_vencimento, public.numero_e164(r.telefone), v_msg,
            case when r.telefone is null then 'erro' else 'pendente' end::public.status_notificacao, r.provedor,
            case when r.telefone is null then 'Cliente sem telefone cadastrado.' end);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Processamento no banco: só o provedor simulado é resolvido aqui. Evolution fica pendente para a Edge Function.
create or replace function public.processar_notificacoes(p_organizacao uuid, p_agora timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare r record; v_hora time := (p_agora at time zone 'America/Sao_Paulo')::time; n int := 0;
begin
  perform set_config('erp.motor', 'on', true);
  for r in
    select g.id, g.lancamento_id, cfg.hora_inicio, cfg.hora_fim, cfg.ativo, cfg.provedor
      from public.notificacoes_log g join public.notificacoes_config cfg on cfg.negocio_id = g.negocio_id
     where g.organizacao_id = p_organizacao and g.status = 'pendente'
     order by g.criado_em
  loop
    if not r.ativo then continue; end if;
    if v_hora < r.hora_inicio or v_hora >= r.hora_fim then continue; end if;
    if r.lancamento_id is not null and exists (select 1 from public.lancamentos l where l.id = r.lancamento_id and l.status <> 'previsto') then
      update public.notificacoes_log set status = 'erro', erro = 'Cobrança já paga ou cancelada antes do envio.' where id = r.id;
      continue;
    end if;
    if r.provedor::text = 'simulado' then
      update public.notificacoes_log set status = 'simulado', data_envio = p_agora where id = r.id;
      n := n + 1;
    end if;
    -- evolution: permanece pendente; a Edge Function envia
  end loop;
  return n;
end;
$$;

-- Teste manual: no provedor evolution fica pendente para envio real; no simulado é registrado como simulado
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
  v_msg := public.renderizar_template(v_tpl, jsonb_build_object('nome', pe.nome, 'negocio', n.nome, 'plano', 'Plano exemplo', 'valor', public.moeda_br(99.90),
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

-- -----------------------------------------------------------------------------
-- Interface para a Edge Function (só service_role)
-- -----------------------------------------------------------------------------
-- Fila pronta para envio: pendentes do provedor evolution, negócio ativo, dentro do horário comercial (agora, Brasília).
-- Cobranças já pagas/canceladas são marcadas como erro aqui e não retornam.
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
  return query
    select g.id, g.negocio_id, cfg.instancia, g.numero_destino, g.mensagem, g.tipo, g.tentativas
      from public.notificacoes_log g
      join public.notificacoes_config cfg on cfg.negocio_id = g.negocio_id
      join public.negocios n on n.id = g.negocio_id
     where g.status = 'pendente' and g.numero_destino is not null and cfg.ativo and n.ativo
       and cfg.provedor::text = 'evolution' and cfg.instancia is not null
       and v_hora >= cfg.hora_inicio and v_hora < cfg.hora_fim
       and g.tentativas < 5
     order by g.criado_em
     limit p_limite;
end;
$$;

create or replace function public.registrar_resultado_notificacao(p_id uuid, p_ok boolean, p_erro text default null, p_resposta jsonb default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('erp.motor', 'on', true);
  if p_ok then
    update public.notificacoes_log set status = 'enviado', data_envio = now(), erro = null, resposta_provedor = p_resposta, tentativas = tentativas + 1 where id = p_id and status = 'pendente';
  else
    -- falha: continua pendente até 5 tentativas; depois vira erro definitivo
    update public.notificacoes_log
       set tentativas = tentativas + 1, erro = left(p_erro, 500), resposta_provedor = p_resposta,
           status = case when tentativas + 1 >= 5 then 'erro'::public.status_notificacao else status end
     where id = p_id and status = 'pendente';
  end if;
end;
$$;

revoke all on function public.notificacoes_para_envio(integer), public.registrar_resultado_notificacao(uuid, boolean, text, jsonb) from public, anon, authenticated;
grant execute on function public.notificacoes_para_envio(integer), public.registrar_resultado_notificacao(uuid, boolean, text, jsonb) to service_role;
