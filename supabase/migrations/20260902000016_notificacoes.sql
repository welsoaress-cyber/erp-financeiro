-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0016: NOTIFICAÇÕES WHATSAPP (Etapa 10, modo simulado)
-- Avisos ao cliente sobre a cobrança do contrato: X dias antes do vencimento,
-- no dia, e Y dias após sem pagamento (bloqueio). Configuração por negócio
-- (número, templates, horário comercial). Fila e histórico em notificacoes_log.
-- NENHUMA mensagem real é enviada: o provedor "simulado" apenas registra.
-- A integração real (Cloud API etc.) entra como outro provedor, sem mudar o esquema.
-- =============================================================================

create type public.tipo_notificacao   as enum ('proximo_vencimento', 'vencimento', 'bloqueio', 'teste');
create type public.status_notificacao as enum ('pendente', 'simulado', 'enviado', 'erro');
create type public.provedor_notificacao as enum ('simulado');

create table public.notificacoes_config (
  id                          uuid primary key default gen_random_uuid(),
  organizacao_id              uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id                  uuid not null unique references public.negocios (id) on delete restrict,
  numero_whatsapp             text check (numero_whatsapp is null or numero_whatsapp ~ '^\+[1-9][0-9]{9,14}$'),
  provedor                    public.provedor_notificacao not null default 'simulado',
  ativo                       boolean not null default false,
  dias_antes                  smallint not null default 3 check (dias_antes between 0 and 30),
  dias_apos                   smallint not null default 3 check (dias_apos between 1 and 60),
  hora_inicio                 time not null default '08:00',
  hora_fim                    time not null default '18:00',
  template_vencimento_proximo text not null default 'Olá {nome}! Sua fatura do {negocio} ({plano}) no valor de {valor} vence em {vencimento}. Qualquer dúvida, fale com a gente.',
  template_vencimento_dia     text not null default 'Olá {nome}! Sua fatura do {negocio} ({plano}) no valor de {valor} vence hoje, {vencimento}. Evite o bloqueio pagando ainda hoje.',
  template_bloqueio           text not null default 'Olá {nome}. Não identificamos o pagamento da fatura do {negocio} ({plano}), {valor}, vencida em {vencimento}. Seu acesso será bloqueado. Se já pagou, desconsidere.',
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now(),
  check (hora_fim > hora_inicio),
  check (char_length(template_vencimento_proximo) between 10 and 1000),
  check (char_length(template_vencimento_dia) between 10 and 1000),
  check (char_length(template_bloqueio) between 10 and 1000),
  check (not ativo or numero_whatsapp is not null)
);
comment on table public.notificacoes_config is 'Configuração de avisos de cobrança por negócio. Placeholders: {nome} {negocio} {plano} {valor} {vencimento} {contrato} {dias}.';

create table public.notificacoes_log (
  id              uuid primary key default gen_random_uuid(),
  organizacao_id  uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id      uuid not null references public.negocios (id) on delete restrict,
  contrato_id     uuid references public.contratos (id) on delete restrict,
  pessoa_id       uuid not null references public.pessoas (id) on delete restrict,
  lancamento_id   uuid references public.lancamentos (id) on delete restrict,
  tipo            public.tipo_notificacao not null,
  data_referencia date not null,
  numero_destino  text,
  mensagem        text not null,
  status          public.status_notificacao not null default 'pendente',
  provedor        public.provedor_notificacao not null default 'simulado',
  erro            text,
  data_envio      timestamptz,
  criado_em       timestamptz not null default now(),
  check ((tipo = 'teste') = (lancamento_id is null)),
  check ((status in ('simulado', 'enviado')) = (data_envio is not null))
);
-- nunca o mesmo aviso para a mesma cobrança
create unique index notificacoes_log_unico_idx on public.notificacoes_log (lancamento_id, tipo) where lancamento_id is not null;
create index notificacoes_log_negocio_idx on public.notificacoes_log (negocio_id, criado_em desc);
create index notificacoes_log_contrato_idx on public.notificacoes_log (contrato_id);
comment on table public.notificacoes_log is 'Fila e histórico de avisos. Só o motor grava. Status simulado = registrado sem envio real.';

-- -----------------------------------------------------------------------------
-- Proteções
-- -----------------------------------------------------------------------------
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
  return new;
end;
$$;
create trigger notificacoes_config_protecao before insert or update on public.notificacoes_config for each row execute function public.tg_notificacoes_config_protecao();
create trigger notificacoes_config_atualizado_em before update on public.notificacoes_config for each row execute function public.tg_atualizado_em();
create trigger notificacoes_config_auditoria after insert or update or delete on public.notificacoes_config for each row execute function public.tg_auditoria();

create or replace function public.tg_notificacoes_log_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not public.motor_ativo() then
    raise exception 'O histórico de notificações só é gravado pelo motor.' using errcode = 'insufficient_privilege';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Notificações não podem ser excluídas.' using errcode = 'check_violation';
  end if;
  if tg_op = 'UPDATE' and (new.mensagem <> old.mensagem or new.tipo <> old.tipo or new.lancamento_id is distinct from old.lancamento_id) then
    raise exception 'Mensagem, tipo e cobrança de uma notificação não mudam.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger notificacoes_log_protecao before insert or update or delete on public.notificacoes_log for each row execute function public.tg_notificacoes_log_protecao();
create trigger notificacoes_log_auditoria after insert or update or delete on public.notificacoes_log for each row execute function public.tg_auditoria();

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
-- Telefone da pessoa (só dígitos) → E.164. 10–11 dígitos = Brasil (+55); 12–13 = já com DDI.
create or replace function public.numero_e164(p_telefone text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_telefone is null then null
    when char_length(p_telefone) between 10 and 11 then '+55' || p_telefone
    else '+' || p_telefone end;
$$;

-- Substitui {chave} pelos valores do jsonb.
create or replace function public.renderizar_template(p_template text, p_vars jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare k text; v text; r text := p_template;
begin
  for k, v in select key, value from jsonb_each_text(p_vars) loop
    r := replace(r, '{' || k || '}', coalesce(v, ''));
  end loop;
  return r;
end;
$$;

create or replace function public.moeda_br(p_valor numeric)
returns text
language sql
immutable
set search_path = public
as $$ select 'R$ ' || replace(replace(replace(to_char(p_valor, 'FM999G999G990D00'), '.', '#'), ',', '.'), '#', ','); $$;

-- -----------------------------------------------------------------------------
-- Motor: gerar avisos devidos (fila) e processar (provedor)
-- -----------------------------------------------------------------------------
-- Para cada cobrança prevista de contrato ativo com config ativa, cria o aviso
-- do tipo devido na data p_data. Idempotente (índice único por cobrança + tipo).
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
       and c.status = 'ativo' and n.ativo and cfg.ativo
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

-- Processa a fila: dentro do horário comercial do negócio, "envia" pelo provedor.
-- Provedor simulado: marca como simulado (nada sai). Cobrança já paga/cancelada antes do envio: erro (não avisar).
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
    if v_hora < r.hora_inicio or v_hora >= r.hora_fim then continue; end if;  -- fora do horário: fica pendente
    if r.lancamento_id is not null and exists (select 1 from public.lancamentos l where l.id = r.lancamento_id and l.status <> 'previsto') then
      update public.notificacoes_log set status = 'erro', erro = 'Cobrança já paga ou cancelada antes do envio.' where id = r.id;
      continue;
    end if;
    -- provedor simulado (único disponível): registra sem enviar
    update public.notificacoes_log set status = 'simulado', data_envio = p_agora, provedor = r.provedor where id = r.id;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Execução completa para uma organização (gera + processa). Retorna contagens.
create or replace function public.executar_notificacoes(p_organizacao uuid, p_data date default current_date, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare g int; p int; pend int;
begin
  g := public.gerar_notificacoes(p_organizacao, p_data);
  p := public.processar_notificacoes(p_organizacao, p_agora);
  select count(*) into pend from public.notificacoes_log where organizacao_id = p_organizacao and status = 'pendente';
  return jsonb_build_object('data', p_data, 'geradas', g, 'processadas', p, 'pendentes', pend);
end;
$$;

-- RPC da interface: organizações do usuário. p_data só para simular outro dia (nunca no futuro distante).
create or replace function public.executar_notificacoes_agora(p_data date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid; r jsonb; total jsonb := '[]'::jsonb;
begin
  if p_data > current_date + 31 then raise exception 'Data muito distante: no máximo 31 dias à frente.' using errcode = 'check_violation'; end if;
  for v_org in select public.minhas_organizacoes() loop
    total := total || public.executar_notificacoes(v_org, p_data, now());
  end loop;
  return total -> 0;
end;
$$;

-- Entrada do agendamento (pg_cron): todas as organizações, hoje.
create or replace function public.executar_notificacoes_todas()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid;
begin
  for v_org in select id from public.organizacoes loop
    perform public.executar_notificacoes(v_org, current_date, now());
  end loop;
end;
$$;

-- Mensagem de teste para um cliente (registrada como teste; provedor simulado não envia).
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
  values (n.organizacao_id, p_negocio_id, p_pessoa_id, 'teste', current_date, public.numero_e164(pe.telefone), '[TESTE] ' || v_msg, 'simulado', cfg.provedor, now())
  returning * into g;
  return g;
end;
$$;

-- View para a interface
create view public.vw_notificacoes
with (security_invoker = true) as
select g.id, g.organizacao_id, g.negocio_id, n.nome as negocio, g.contrato_id, c.codigo as contrato_codigo, g.pessoa_id, pe.nome as pessoa,
       g.lancamento_id, g.tipo, g.data_referencia, g.numero_destino, g.mensagem, g.status, g.provedor, g.erro, g.data_envio, g.criado_em
  from public.notificacoes_log g
  join public.negocios n on n.id = g.negocio_id
  join public.pessoas pe on pe.id = g.pessoa_id
  left join public.contratos c on c.id = g.contrato_id;

-- -----------------------------------------------------------------------------
-- Permissões e RLS
-- -----------------------------------------------------------------------------
alter table public.notificacoes_config enable row level security;
alter table public.notificacoes_log enable row level security;
create policy notificacoes_config_select on public.notificacoes_config for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy notificacoes_config_insert on public.notificacoes_config for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy notificacoes_config_update on public.notificacoes_config for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy notificacoes_log_select on public.notificacoes_log for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.notificacoes_config, public.notificacoes_log from public, anon, authenticated;
grant select, insert, update on public.notificacoes_config to authenticated;
grant select on public.notificacoes_log, public.vw_notificacoes to authenticated;
revoke all on function public.tg_notificacoes_config_protecao(), public.tg_notificacoes_log_protecao() from public, anon, authenticated;
revoke all on function public.numero_e164(text), public.renderizar_template(text, jsonb), public.moeda_br(numeric) from public, anon;
grant execute on function public.numero_e164(text), public.renderizar_template(text, jsonb), public.moeda_br(numeric) to authenticated;
revoke all on function public.gerar_notificacoes(uuid, date), public.processar_notificacoes(uuid, timestamptz), public.executar_notificacoes(uuid, date, timestamptz), public.executar_notificacoes_todas() from public, anon, authenticated;
revoke all on function public.executar_notificacoes_agora(date), public.enviar_notificacao_teste(uuid, uuid, text) from public, anon;
grant execute on function public.executar_notificacoes_agora(date), public.enviar_notificacao_teste(uuid, uuid, text) to authenticated;
