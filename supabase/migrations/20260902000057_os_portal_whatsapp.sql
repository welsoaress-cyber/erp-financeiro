-- =============================================================================
-- 0057 · Etapa 29C — Chamado técnico pelo Portal + avisos WhatsApp da OS
-- =============================================================================
-- Portal: o cliente abre uma VISITA TÉCNICA que vira uma OS de verdade
-- (aberto_via = portal, técnico atribuído automaticamente — regra da 0055).
-- As solicitações antigas do portal (fatura/dúvida/upgrade) continuam como são.
-- O cliente acompanha o status, aprova/recusa a remarcação pedida pelo técnico
-- (aval de quem abriu) e avalia o chamado encerrado ("foi resolvido?" + nota;
-- não resolvido pode reabrir — vira chamado novo numero-A, mesma regra do admin).
-- WhatsApp: ao agendar (e ao aprovar remarcação) e ao encerrar, entra um aviso
-- na fila existente de notificações (notificacoes_log): provedor evolution fica
-- pendente e a Edge Function envia; simulado registra na hora. Exige config de
-- notificações ativa no negócio, telefone do cliente e receber_avisos ligado.
-- =============================================================================

-- novos tipos de aviso (comparações por ::text para poder usar na mesma migration)
alter type public.tipo_notificacao add value if not exists 'os_agendada';
alter type public.tipo_notificacao add value if not exists 'os_encerrada';
alter table public.notificacoes_log add column os_id uuid references public.ordens_servico (id);

-- o check antigo exigia lancamento_id em tudo que não fosse teste; avisos de OS não têm lançamento
do $$ declare v_con text;
begin
  select conname into v_con from pg_constraint
   where conrelid = 'public.notificacoes_log'::regclass and pg_get_constraintdef(oid) like '%teste%';
  if v_con is not null then execute 'alter table public.notificacoes_log drop constraint ' || quote_ident(v_con); end if;
end $$;
alter table public.notificacoes_log add constraint notificacoes_log_lancamento_chk
  check ((lancamento_id is null) = (tipo::text in ('teste', 'os_agendada', 'os_encerrada')));
alter table public.notificacoes_log add constraint notificacoes_log_os_chk
  check (os_id is null or tipo::text in ('os_agendada', 'os_encerrada'));
create index notificacoes_log_os_idx on public.notificacoes_log (os_id) where os_id is not null;

-- Enfileira o aviso da OS se: cliente com telefone e receber_avisos, config ativa do negócio.
create function public.os_notificar(p_os_id uuid, p_tipo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  os public.ordens_servico%rowtype; pe public.pessoas%rowtype; cfg public.notificacoes_config%rowtype;
  t text; v_msg text;
begin
  select * into os from public.ordens_servico where id = p_os_id;
  if os.pessoa_id is null then return; end if;
  select * into pe from public.pessoas where id = os.pessoa_id;
  if pe.telefone is null or not pe.receber_avisos then return; end if;
  select * into cfg from public.notificacoes_config where negocio_id = os.negocio_id;
  if cfg.id is null or not cfg.ativo then return; end if;
  -- encerramento avisa uma vez só; agendamento pode repetir (remarcação)
  if p_tipo = 'os_encerrada' and exists (select 1 from public.notificacoes_log where os_id = p_os_id and tipo::text = 'os_encerrada') then return; end if;
  select nome into t from public.tecnicos where id = os.tecnico_id;
  if p_tipo = 'os_agendada' then
    if os.data_agendada is null then return; end if;
    v_msg := 'Olá ' || split_part(pe.nome, ' ', 1) || '! Sua visita técnica (' || os.numero || ') foi agendada para '
          || to_char(os.data_agendada, 'DD/MM/YYYY') || ' às ' || to_char(os.hora_agendada, 'HH24:MI')
          || coalesce(' com o técnico ' || t, '') || '.';
  else
    v_msg := 'Olá ' || split_part(pe.nome, ' ', 1) || '! Seu chamado ' || os.numero || ' foi concluído. '
          || 'Se puder, avalie o atendimento no portal. Qualquer problema, é só chamar.';
  end if;
  perform set_config('erp.motor', 'on', true);
  insert into public.notificacoes_log (organizacao_id, negocio_id, contrato_id, pessoa_id, os_id, tipo, data_referencia, numero_destino, mensagem, status, provedor, data_envio)
  values (os.organizacao_id, os.negocio_id, os.contrato_id, os.pessoa_id, os.id, p_tipo::public.tipo_notificacao, current_date,
          public.numero_e164(pe.telefone), v_msg,
          case when cfg.provedor::text = 'evolution' then 'pendente' else 'simulado' end::public.status_notificacao,
          cfg.provedor, case when cfg.provedor::text = 'evolution' then null else now() end);
end;
$$;
revoke all on function public.os_notificar(uuid, text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Núcleo de abertura reutilizável (admin e portal) — corpo da 0055 sem permissão
-- -----------------------------------------------------------------------------
create function public.os_abrir_interna(
  p_negocio_id uuid, p_tipo text, p_descricao text,
  p_pessoa_id uuid, p_contrato_id uuid, p_tecnico_id uuid,
  p_cto_id uuid, p_prioridade text, p_aberto_via text, p_os_origem_id uuid
)
returns public.ordens_servico
language plpgsql
security definer
set search_path = public
as $$
declare
  n public.negocios%rowtype; ct public.contratos%rowtype; os public.ordens_servico%rowtype;
  v_tecnico uuid := p_tecnico_id; v_numero text; v_base text; v_letra int; v_retorno boolean;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  if p_pessoa_id is not null and not exists (select 1 from public.pessoas where id = p_pessoa_id and organizacao_id = n.organizacao_id) then
    raise exception 'Cliente inválido.' using errcode = 'check_violation';
  end if;
  if p_contrato_id is not null then
    select * into ct from public.contratos where id = p_contrato_id;
    if ct.id is null or ct.pessoa_id is distinct from p_pessoa_id or ct.negocio_id <> p_negocio_id then
      raise exception 'Contrato inválido: precisa ser do cliente e do negócio do chamado.' using errcode = 'check_violation';
    end if;
  end if;
  if p_cto_id is not null and not exists (select 1 from public.ctos where id = p_cto_id and negocio_id = p_negocio_id) then
    raise exception 'CTO inválida.' using errcode = 'check_violation';
  end if;
  if v_tecnico is null then
    select t.id into v_tecnico
      from public.tecnicos t
      left join public.ordens_servico o on o.tecnico_id = t.id and o.status in ('aberto', 'em_atendimento', 'pausado')
     where t.negocio_id = p_negocio_id and t.ativo
     group by t.id order by count(o.id), t.criado_em limit 1;
  elsif not exists (select 1 from public.tecnicos where id = v_tecnico and negocio_id = p_negocio_id and ativo) then
    raise exception 'Técnico inválido para este negócio.' using errcode = 'check_violation';
  end if;
  if p_os_origem_id is not null then
    select numero into v_base from public.ordens_servico where id = p_os_origem_id and organizacao_id = n.organizacao_id;
    if v_base is null then raise exception 'Chamado de origem inválido.' using errcode = 'check_violation'; end if;
    select count(*) into v_letra from public.ordens_servico where os_origem_id = p_os_origem_id;
    v_numero := v_base || '-' || chr(65 + v_letra);
  else
    v_base := case when ct.id is not null then 'OS' || lpad(ct.codigo::text, 3, '0') else 'MAN' end || to_char(current_date, 'DDMMYYYY');
    select count(*) into v_letra from public.ordens_servico where organizacao_id = n.organizacao_id and numero like v_base || '_' and os_origem_id is null;
    v_numero := v_base || chr(65 + v_letra);
  end if;
  v_retorno := p_pessoa_id is not null and p_os_origem_id is null and exists (
    select 1 from public.ordens_servico where pessoa_id = p_pessoa_id and status = 'encerrado' and data_fim >= now() - interval '7 days');

  perform set_config('erp.motor', 'on', true);
  insert into public.ordens_servico (organizacao_id, negocio_id, numero, os_origem_id, retorno, contrato_id, pessoa_id, tecnico_id, cto_id, tipo, prioridade, aberto_via, descricao, usuario_abertura)
  values (n.organizacao_id, p_negocio_id, v_numero, p_os_origem_id, v_retorno, p_contrato_id, p_pessoa_id, v_tecnico, p_cto_id,
          p_tipo::public.tipo_os, p_prioridade::public.prioridade_os, p_aberto_via::public.origem_abertura_os, btrim(p_descricao), auth.uid())
  returning * into os;
  perform public.os_registrar_evento(os.id, case when p_os_origem_id is null then 'abertura' else 'reabertura' end::public.evento_os, 'Via ' || p_aberto_via);
  if v_tecnico is not null then perform public.os_registrar_evento(os.id, 'atribuicao', (select nome from public.tecnicos where id = v_tecnico)); end if;
  return os;
end;
$$;
revoke all on function public.os_abrir_interna(uuid, text, text, uuid, uuid, uuid, uuid, text, text, uuid) from public, anon, authenticated;

-- abrir_os do admin passa a delegar
create or replace function public.abrir_os(
  p_negocio_id uuid, p_tipo text, p_descricao text,
  p_pessoa_id uuid default null, p_contrato_id uuid default null, p_tecnico_id uuid default null,
  p_cto_id uuid default null, p_prioridade text default 'normal', p_aberto_via text default 'admin',
  p_os_origem_id uuid default null
)
returns public.ordens_servico
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid;
begin
  select organizacao_id into v_org from public.negocios where id = p_negocio_id;
  if v_org is null then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(v_org);
  return public.os_abrir_interna(p_negocio_id, p_tipo, p_descricao, p_pessoa_id, p_contrato_id, p_tecnico_id, p_cto_id, p_prioridade, p_aberto_via, p_os_origem_id);
end;
$$;

-- agendar/aprovar remarcação/encerrar passam a avisar o cliente no WhatsApp
create or replace function public.agendar_os(p_os_id uuid, p_data date, p_hora time)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare os public.ordens_servico%rowtype;
begin
  select * into os from public.ordens_servico where id = p_os_id;
  if not found then raise exception 'Chamado não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro_ou_tecnico_os(os);
  if os.status not in ('aberto', 'pausado') then raise exception 'Chamado % não aceita agendamento.', os.numero using errcode = 'check_violation'; end if;
  if p_data is null or p_hora is null then raise exception 'Informe data e hora do atendimento.' using errcode = 'check_violation'; end if;
  if os.data_agendada is not null and os.status = 'aberto' and os.data_inicio is null then
    raise exception 'Chamado já agendado: peça remarcação (aval de quem abriu).' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set data_agendada = p_data, hora_agendada = p_hora where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'agendamento', to_char(p_data, 'DD/MM/YYYY') || ' ' || to_char(p_hora, 'HH24:MI'));
  perform public.os_notificar(p_os_id, 'os_agendada');
end;
$$;

create or replace function public.responder_remarcacao_os(p_os_id uuid, p_aprovar boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare os public.ordens_servico%rowtype;
begin
  select * into os from public.ordens_servico where id = p_os_id;
  if not found then raise exception 'Chamado não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(os.organizacao_id);
  if os.remarcacao_data is null then raise exception 'Não há remarcação pendente.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico
     set data_agendada = case when p_aprovar then remarcacao_data else data_agendada end,
         hora_agendada = case when p_aprovar then remarcacao_hora else hora_agendada end,
         remarcacao_data = null, remarcacao_hora = null, remarcacao_motivo = null
   where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'remarcacao_respondida', case when p_aprovar then 'Aprovada' else 'Recusada' end);
  if p_aprovar then perform public.os_notificar(p_os_id, 'os_agendada'); end if;
end;
$$;

create or replace function public.encerrar_os(
  p_os_id uuid, p_itens jsonb default '[]'::jsonb, p_diagnostico text default null,
  p_sinal_dbm numeric default null, p_observacao text default null
)
returns public.ordens_servico
language plpgsql
security definer
set search_path = public
as $$
declare
  os public.ordens_servico%rowtype; linha jsonb; v_item uuid; v_qtd numeric; v_custo numeric; v_material numeric := 0;
  v_agendado timestamptz; v_pausa int; v_ins public.estoque_instalacoes%rowtype;
begin
  select * into os from public.ordens_servico where id = p_os_id;
  if not found then raise exception 'Chamado não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro_ou_tecnico_os(os);
  if os.status not in ('em_atendimento', 'pausado') then raise exception 'Inicie o atendimento antes de encerrar.' using errcode = 'check_violation'; end if;
  if p_itens is not null and jsonb_typeof(p_itens) <> 'array' then raise exception 'Materiais devem ser uma lista.' using errcode = 'check_violation'; end if;
  if jsonb_array_length(coalesce(p_itens, '[]'::jsonb)) > 0 and os.tecnico_id is null then
    raise exception 'Chamado sem técnico não consome materiais.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  v_pausa := os.tempo_pausa_minutos + case when os.status = 'pausado' then greatest(0, floor(extract(epoch from (now() - os.pausado_em)) / 60))::int else 0 end;
  v_agendado := (os.data_agendada + os.hora_agendada)::timestamptz;

  for linha in select * from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) loop
    v_item := (linha->>'item_id')::uuid;
    v_qtd := (linha->>'quantidade')::numeric;
    if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade inválida no material.' using errcode = 'check_violation'; end if;
    v_custo := public.os_mover_bolsa(os.tecnico_id, v_item, -v_qtd, 'consumo', null, false, os.id);
    insert into public.os_materiais (organizacao_id, os_id, item_id, quantidade, valor_unitario, valor_total)
    values (os.organizacao_id, os.id, v_item, v_qtd, v_custo, round(v_qtd * v_custo, 2));
    v_material := v_material + round(v_qtd * v_custo, 2);
  end loop;

  update public.ordens_servico
     set status = 'encerrado', data_fim = now(), pausado_em = null,
         tempo_pausa_minutos = v_pausa,
         tempo_total_minutos = greatest(0, floor(extract(epoch from (now() - v_agendado)) / 60))::int - v_pausa,
         tempo_execucao_minutos = case when data_inicio is not null then greatest(0, floor(extract(epoch from (now() - data_inicio)) / 60))::int - v_pausa end,
         diagnostico = p_diagnostico::public.diagnostico_os,
         sinal_dbm = p_sinal_dbm,
         observacao = coalesce(p_observacao, observacao)
   where id = p_os_id returning * into os;

  if os.tipo in ('instalacao', 'mudanca_endereco') and os.contrato_id is not null and v_material > 0 then
    insert into public.estoque_instalacoes (organizacao_id, negocio_id, pessoa_id, contrato_id, os_id, data, custo_material, mao_de_obra, tecnico, observacao, usuario_id)
    values (os.organizacao_id, os.negocio_id, os.pessoa_id, os.contrato_id, os.id, current_date, v_material, 0,
            (select nome from public.tecnicos where id = os.tecnico_id), 'Chamado ' || os.numero, auth.uid())
    returning * into v_ins;
  end if;
  perform public.os_registrar_evento(p_os_id, 'encerramento', 'Material ' || to_char(v_material, 'FM999999990.00'));
  perform public.os_notificar(p_os_id, 'os_encerrada');
  return os;
end;
$$;

-- -----------------------------------------------------------------------------
-- Portal: visita técnica vira OS
-- -----------------------------------------------------------------------------
-- p_problema: sem_internet | lentidao | mudanca_endereco | outro
create function public.portal_abrir_visita(p_negocio_id uuid, p_problema text, p_descricao text)
returns table (numero text, tecnico text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pe uuid := public.portal_pessoa(); v_ct public.contratos%rowtype; os public.ordens_servico%rowtype;
  v_tipo text; v_rotulo text;
begin
  if v_pe is null then raise exception 'Acesso ao portal não vinculado.' using errcode = 'insufficient_privilege'; end if;
  select * into v_ct from public.contratos
   where pessoa_id = v_pe and negocio_id = p_negocio_id and status = 'ativo' and tipo_financeiro = 'receita'
   order by criado_em desc limit 1;
  if v_ct.id is null then raise exception 'Você não tem contrato ativo neste serviço.' using errcode = 'check_violation'; end if;
  if (select count(*) from public.ordens_servico where pessoa_id = v_pe and aberto_via = 'portal' and criado_em > now() - interval '1 day') >= 5 then
    raise exception 'Limite de chamados por dia atingido. Fale com o suporte.' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.ordens_servico where pessoa_id = v_pe and status in ('aberto', 'em_atendimento', 'pausado') and aberto_via = 'portal') then
    raise exception 'Você já tem uma visita em andamento. Acompanhe pelo portal.' using errcode = 'check_violation';
  end if;
  v_tipo := case p_problema when 'mudanca_endereco' then 'mudanca_endereco' when 'outro' then 'manutencao' else 'reparo' end;
  v_rotulo := case p_problema when 'sem_internet' then 'Sem internet' when 'lentidao' then 'Internet lenta' when 'mudanca_endereco' then 'Mudança de endereço' else 'Outro' end;
  os := public.os_abrir_interna(p_negocio_id, v_tipo, v_rotulo || coalesce(': ' || nullif(btrim(p_descricao), ''), ''),
                                v_pe, v_ct.id, null, null, case when p_problema = 'sem_internet' then 'urgente' else 'normal' end, 'portal', null);
  return query select os.numero, (select t.nome from public.tecnicos t where t.id = os.tecnico_id);
end;
$$;

-- Acompanhamento do cliente (sem tempos internos)
create function public.portal_minhas_visitas()
returns table (id uuid, numero text, tipo public.tipo_os, status public.status_os, descricao text,
               data_agendada date, hora_agendada time, remarcacao_data date, remarcacao_hora time, remarcacao_motivo text,
               tecnico text, avaliacao_resolvido boolean, avaliacao_nota smallint, aberto_via public.origem_abertura_os, criado_em timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select o.id, o.numero, o.tipo, o.status, o.descricao,
         o.data_agendada, o.hora_agendada, o.remarcacao_data, o.remarcacao_hora, o.remarcacao_motivo,
         t.nome, o.avaliacao_resolvido, o.avaliacao_nota, o.aberto_via, o.criado_em
    from public.ordens_servico o
    left join public.tecnicos t on t.id = o.tecnico_id
   where o.pessoa_id = public.portal_pessoa()
   order by o.criado_em desc limit 50;
$$;

-- Aval do cliente à remarcação (só em chamado que ELE abriu pelo portal)
create function public.portal_responder_remarcacao(p_os_id uuid, p_aprovar boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare os public.ordens_servico%rowtype;
begin
  select * into os from public.ordens_servico where id = p_os_id;
  if os.id is null or os.pessoa_id is distinct from public.portal_pessoa() or os.aberto_via <> 'portal' then
    raise exception 'Chamado não encontrado.' using errcode = 'insufficient_privilege';
  end if;
  if os.remarcacao_data is null then raise exception 'Não há remarcação pendente.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico
     set data_agendada = case when p_aprovar then remarcacao_data else data_agendada end,
         hora_agendada = case when p_aprovar then remarcacao_hora else hora_agendada end,
         remarcacao_data = null, remarcacao_hora = null, remarcacao_motivo = null
   where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'remarcacao_respondida', case when p_aprovar then 'Aprovada pelo cliente' else 'Recusada pelo cliente' end);
  if p_aprovar then perform public.os_notificar(p_os_id, 'os_agendada'); end if;
end;
$$;

-- Avaliação do cliente; não resolvido pode reabrir (chamado novo -A, urgente)
create function public.portal_avaliar_visita(p_os_id uuid, p_resolvido boolean, p_nota int default null, p_reabrir boolean default false)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare os public.ordens_servico%rowtype;
begin
  select * into os from public.ordens_servico where id = p_os_id;
  if os.id is null or os.pessoa_id is distinct from public.portal_pessoa() or os.aberto_via <> 'portal' then
    raise exception 'Chamado não encontrado.' using errcode = 'insufficient_privilege';
  end if;
  if os.status <> 'encerrado' then raise exception 'Só chamado encerrado é avaliado.' using errcode = 'check_violation'; end if;
  if os.avaliacao_resolvido is not null then raise exception 'Chamado já avaliado.' using errcode = 'check_violation'; end if;
  if p_resolvido and (p_nota is null or p_nota not between 1 and 5) then raise exception 'Nota de 1 a 5.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set avaliacao_resolvido = p_resolvido, avaliacao_nota = case when p_resolvido then p_nota end where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'avaliacao', case when p_resolvido then 'Resolvido, nota ' || p_nota else 'Não resolvido' end || ' (cliente)');
  if not p_resolvido and p_reabrir then
    perform public.os_abrir_interna(os.negocio_id, os.tipo::text, 'Reabertura: ' || os.descricao,
                                    os.pessoa_id, os.contrato_id, os.tecnico_id, os.cto_id, 'urgente', 'portal', os.id);
  end if;
end;
$$;

revoke all on function public.portal_abrir_visita(uuid, text, text), public.portal_minhas_visitas(),
  public.portal_responder_remarcacao(uuid, boolean), public.portal_avaliar_visita(uuid, boolean, int, boolean)
from public, anon;
grant execute on function public.portal_abrir_visita(uuid, text, text), public.portal_minhas_visitas(),
  public.portal_responder_remarcacao(uuid, boolean), public.portal_avaliar_visita(uuid, boolean, int, boolean)
to authenticated;
