-- =============================================================================
-- Migration 0024: PORTAL — EXPERIÊNCIA DO PORTAL ANTIGO DA SERVNET (Etapa 11B)
-- Login por CPF + data de nascimento (sem senha, via Edge Function portal-login),
-- status da rede, Programa Fidelidade (12 selos: 6 em dia = 50%, 12 = 100% na
-- fatura seguinte), Indique e Ganhe com "1 mês grátis", meus dados, chamados.
-- =============================================================================

-- 1. Pessoa: data de nascimento (login do portal) 
alter table public.pessoas add column data_nascimento date check (data_nascimento is null or data_nascimento between date '1900-01-01' and current_date);

-- 2. Config do portal: tema, WhatsApp de suporte, tipo de benefício, fidelidade
create type public.beneficio_indicacao_tipo as enum ('valor', 'mes_gratis');
alter table public.portal_config
  add column tema             text not null default 'escuro' check (tema in ('escuro', 'claro')),
  add column whatsapp_suporte text check (whatsapp_suporte is null or whatsapp_suporte ~ '^\+[1-9][0-9]{9,14}$'),
  add column beneficio_tipo   public.beneficio_indicacao_tipo not null default 'mes_gratis',
  add column fidelidade_ativa boolean not null default true,
  add column site_url         text check (site_url is null or site_url ~ '^https://');
comment on column public.portal_config.beneficio_tipo is 'valor = beneficio_indicacao em R$; mes_gratis = 100% da próxima fatura do indicador.';

-- 3. Status da rede por negócio
create type public.status_rede as enum ('ok', 'lentidao', 'queda', 'manutencao');
create table public.portal_status_rede (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null unique references public.negocios (id) on delete restrict,
  status         public.status_rede not null default 'ok',
  titulo         text check (titulo is null or char_length(titulo) <= 120),
  descricao      text check (descricao is null or char_length(descricao) <= 500),
  atualizado_em  timestamptz not null default now()
);
create trigger portal_status_rede_atualizado_em before update on public.portal_status_rede for each row execute function public.tg_atualizado_em();
create trigger portal_status_rede_auditoria after insert or update or delete on public.portal_status_rede for each row execute function public.tg_auditoria();

-- 4. Solicitações do cliente (chamados/upgrade)
create type public.tipo_solicitacao   as enum ('suporte', 'fatura', 'duvida', 'upgrade');
create type public.status_solicitacao as enum ('aberta', 'em_andamento', 'concluida');
create table public.portal_solicitacoes (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  pessoa_id      uuid not null references public.pessoas (id) on delete restrict,
  contrato_id    uuid references public.contratos (id) on delete restrict,
  tipo           public.tipo_solicitacao not null,
  descricao      text check (descricao is null or char_length(descricao) <= 1000),
  protocolo      text not null unique,
  status         public.status_solicitacao not null default 'aberta',
  resposta       text check (resposta is null or char_length(resposta) <= 1000),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create index portal_solicitacoes_negocio_idx on public.portal_solicitacoes (negocio_id, status, criado_em desc);
create trigger portal_solicitacoes_atualizado_em before update on public.portal_solicitacoes for each row execute function public.tg_atualizado_em();
create trigger portal_solicitacoes_auditoria after insert or update or delete on public.portal_solicitacoes for each row execute function public.tg_auditoria();

-- 5. Descontos: referência única (fidelidade não pode premiar duas vezes o mesmo mês)
alter table public.descontos_contrato add column referencia text;
create unique index descontos_contrato_referencia_idx on public.descontos_contrato (contrato_id, referencia) where referencia is not null;

-- 6. Tentativas de login por CPF (freio para o login sem senha)
create table public.portal_login_tentativas (
  documento    text primary key,
  tentativas   smallint not null default 0,
  bloqueado_ate timestamptz,
  atualizado_em timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Programa Fidelidade: cartão de 12 competências por contrato
-- -----------------------------------------------------------------------------
-- Selo = cobrança paga até o vencimento (ou mês grátis). O cartão começa na 1ª competência do
-- contrato e avança de 12 em 12 até conter a competência de referência.
-- Prêmios: 6º selo → 50% na competência seguinte; 12º selo → 100% na seguinte.
create or replace function public.fidelidade_cartao(p_contrato uuid, p_referencia date default current_date)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  c public.contratos%rowtype; v_ini date; v_ref date := date_trunc('month', p_referencia)::date; v_ciclo int := 1;
  v_slots jsonb := '[]'::jsonb; v_premios jsonb := '[]'::jsonb; v_selos int := 0; i int; v_comp date; r record; v_estado text; v_slot jsonb;
begin
  select * into c from public.contratos where id = p_contrato;
  if not found or c.periodicidade <> 'mensal' then return null; end if;
  v_ini := date_trunc('month', coalesce(c.faturar_desde, c.data_inicio))::date;
  while (v_ini + interval '12 months')::date <= v_ref loop v_ini := (v_ini + interval '12 months')::date; v_ciclo := v_ciclo + 1; end loop;
  for i in 0..11 loop
    v_comp := (v_ini + (i || ' months')::interval)::date;
    select l.status, l.data_vencimento, l.data_efetivacao, l.valor into r
      from public.faturamentos f join public.lancamentos l on l.id = f.lancamento_id
     where f.contrato_id = p_contrato and f.competencia = v_comp
       and (l.status <> 'cancelado' or l.motivo_cancelamento like 'Mês grátis%') limit 1;
    if not found then v_estado := 'vazio';
    elsif r.status = 'cancelado' then v_estado := 'gratis';
    elsif r.status = 'efetivado' then v_estado := case when r.data_efetivacao <= r.data_vencimento then 'ok' else 'atraso' end;
    elsif r.data_vencimento < current_date then v_estado := 'vencida';
    else v_estado := 'aberto'; end if;
    if v_estado in ('ok', 'gratis') then
      v_selos := v_selos + 1;
      if v_selos = 6 then v_premios := v_premios || jsonb_build_object('percentual', 50, 'competencia', (v_ini + ((i + 1) || ' months')::interval)::date, 'referencia', 'fidelidade:' || to_char(v_ini, 'YYYY-MM') || ':50'); end if;
      if v_selos = 12 then v_premios := v_premios || jsonb_build_object('percentual', 100, 'competencia', (v_ini + interval '12 months')::date, 'referencia', 'fidelidade:' || to_char(v_ini, 'YYYY-MM') || ':100'); end if;
    end if;
    v_slot := jsonb_build_object('n', i + 1, 'competencia', v_comp, 'estado', v_estado,
                                 'vencimento', case when found then r.data_vencimento end, 'valor', case when found then r.valor end);
    v_slots := v_slots || v_slot;
  end loop;
  return jsonb_build_object('contrato_id', p_contrato, 'inicio', v_ini, 'fim', (v_ini + interval '11 months')::date, 'ciclo', v_ciclo,
                            'selos', v_selos, 'slots', v_slots, 'premios', v_premios);
end;
$$;

-- Registra (uma vez) o desconto de fidelidade devido para a competência que está sendo faturada
create or replace function public.fidelidade_registrar_premio(p_contrato uuid, p_competencia date)
returns void
language plpgsql
set search_path = public
as $$
declare c public.contratos%rowtype; cfg public.portal_config%rowtype; cartao jsonb; p jsonb; v_valor numeric(14,2);
begin
  select * into c from public.contratos where id = p_contrato;
  select * into cfg from public.portal_config where negocio_id = c.negocio_id;
  if not found or not cfg.fidelidade_ativa then return; end if;
  cartao := public.fidelidade_cartao(p_contrato, (p_competencia - interval '1 month')::date);
  if cartao is null then return; end if;
  for p in select * from jsonb_array_elements(cartao -> 'premios') loop
    if (p ->> 'competencia')::date = p_competencia then
      v_valor := round(c.valor * (p ->> 'percentual')::numeric / 100, 2);
      if v_valor > 0 then
        insert into public.descontos_contrato (organizacao_id, contrato_id, valor, motivo, referencia)
        values (c.organizacao_id, p_contrato, v_valor,
                'Programa Fidelidade: ' || case when (p ->> 'percentual') = '100' then '12 meses em dia (100%)' else '6 meses em dia (50%)' end,
                p ->> 'referencia')
        on conflict (contrato_id, referencia) where referencia is not null do nothing;
      end if;
    end if;
  end loop;
end;
$$;

-- Faturamento: aplica prêmio de fidelidade da competência + descontos pendentes
create or replace function public.faturar_contrato(p_contrato uuid, p_ate date, out gerados integer, out pendencia text)
language plpgsql
set search_path = public
as $$
declare
  c public.contratos%rowtype;
  n public.negocios%rowtype;
  pl public.planos%rowtype;
  v_conta uuid; v_cat uuid; v_comp date; v_venc date; l public.lancamentos%rowtype;
  v_desc numeric(14,2); v_valor numeric(14,2); v_motivos text;
begin
  gerados := 0; pendencia := null;
  select * into c from public.contratos where id = p_contrato;
  if not found or c.status <> 'ativo' or not c.faturamento_automatico then return; end if;
  if not exists (select 1 from public.competencias_pendentes(c.id, p_ate)) then return; end if;
  select * into n from public.negocios where id = c.negocio_id;
  select * into pl from public.planos where id = c.plano_id;
  v_conta := coalesce(c.conta_id, n.conta_padrao_id);
  v_cat := n.categoria_receita_id;
  if v_conta is null then pendencia := 'Sem conta de recebimento (no contrato ou padrão do negócio).'; return; end if;
  if v_cat is null then pendencia := 'Negócio sem categoria de receita padrão.'; return; end if;
  if not exists (select 1 from public.contas where id = v_conta and ativo) then pendencia := 'Conta de recebimento inativa.'; return; end if;
  if not exists (select 1 from public.categorias where id = v_cat and ativo) then pendencia := 'Categoria de receita padrão inativa.'; return; end if;
  if c.valor <= 0 then pendencia := 'Contrato com valor zero.'; return; end if;

  perform set_config('erp.motor', 'on', true);
  for v_comp in select * from public.competencias_pendentes(c.id, p_ate) order by 1 loop
    v_venc := public.data_vencimento_no_mes(v_comp, c.dia_vencimento);
    perform public.fidelidade_registrar_premio(c.id, v_comp);
    select coalesce(sum(d.valor), 0), string_agg(d.motivo, '; ' order by d.criado_em) into v_desc, v_motivos
      from public.descontos_contrato d where d.contrato_id = c.id and d.lancamento_id is null;
    -- desconto igual ou maior que o valor = mês grátis: a cobrança nasce cancelada (sem movimento financeiro)
    v_valor := case when v_desc >= c.valor then c.valor else c.valor - v_desc end;
    insert into public.lancamentos (
      organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
      conta_id, categoria_id, origem, negocio_id, pessoa_id, contrato_id, observacao, cancelado_em, motivo_cancelamento
    ) values (
      c.organizacao_id, 'receita',
      left(pl.nome || ' · ' || to_char(v_comp, 'MM/YYYY') || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140),
      v_valor, v_venc, v_venc, null, (case when v_desc >= c.valor then 'cancelado' else 'previsto' end)::public.status_lancamento,
      v_conta, v_cat, 'faturamento', c.negocio_id, c.pessoa_id, c.id,
      case when v_desc >= c.valor then left('Mês grátis (' || v_motivos || ').', 500)
           when v_desc > 0 then left('Desconto aplicado: ' || public.moeda_br(v_desc) || ' (' || v_motivos || ').', 500) end,
      case when v_desc >= c.valor then now() end,
      case when v_desc >= c.valor then left('Mês grátis: ' || v_motivos, 200) end
    ) returning * into l;
    if v_desc > 0 then
      update public.descontos_contrato set lancamento_id = l.id where contrato_id = c.id and lancamento_id is null;
    end if;
    insert into public.faturamentos (organizacao_id, contrato_id, competencia, lancamento_id) values (c.organizacao_id, c.id, v_comp, l.id);
    gerados := gerados + 1;
  end loop;
end;
$$;

-- Indique e Ganhe: "1 mês grátis" (100% da próxima fatura) ou valor fixo, conforme a config
create or replace function public.converter_indicacao(p_indicacao_id uuid, p_indicado_pessoa_id uuid)
returns public.indicacoes
language plpgsql security definer set search_path = public as $$
declare i public.indicacoes%rowtype; pc public.portal_config%rowtype; c public.contratos%rowtype; v_desc uuid; v_valor numeric(14,2) := 0; v_motivo text;
begin
  select * into i from public.indicacoes where id = p_indicacao_id;
  if not found then raise exception 'Indicação não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(i.organizacao_id);
  if i.status <> 'pendente' then raise exception 'Só indicações pendentes podem ser convertidas.' using errcode = 'check_violation'; end if;
  if not exists (select 1 from public.pessoas where id = p_indicado_pessoa_id and organizacao_id = i.organizacao_id) then
    raise exception 'Pessoa indicada inválida.' using errcode = 'check_violation';
  end if;
  if p_indicado_pessoa_id = i.indicador_pessoa_id then raise exception 'O indicado não pode ser o próprio indicador.' using errcode = 'check_violation'; end if;
  select * into pc from public.portal_config where negocio_id = i.negocio_id;
  select * into c from public.contratos where pessoa_id = i.indicador_pessoa_id and negocio_id = i.negocio_id and status = 'ativo' order by data_inicio desc limit 1;
  perform set_config('erp.motor', 'on', true);
  if found and pc.id is not null then
    if pc.beneficio_tipo = 'mes_gratis' then v_valor := c.valor; v_motivo := 'Indique e Ganhe: 1 mês grátis (indicação de ' || i.nome_indicado || ')';
    else v_valor := pc.beneficio_indicacao; v_motivo := 'Indique e Ganhe: indicação de ' || i.nome_indicado; end if;
    if v_valor > 0 then
      insert into public.descontos_contrato (organizacao_id, contrato_id, valor, motivo, indicacao_id, referencia)
      values (i.organizacao_id, c.id, v_valor, v_motivo, i.id, 'indicacao:' || i.id::text) returning id into v_desc;
    end if;
  end if;
  update public.indicacoes set status = 'convertida', indicado_pessoa_id = p_indicado_pessoa_id, beneficio_valor = case when v_desc is null then 0 else v_valor end, desconto_id = v_desc
   where id = i.id returning * into i;
  return i;
end; $$;

-- -----------------------------------------------------------------------------
-- Login sem senha (CPF + data de nascimento) — só a Edge Function (service_role)
-- -----------------------------------------------------------------------------
-- Verifica CPF/CNPJ + nascimento com freio: 5 falhas → 15 minutos bloqueado.
create or replace function public.portal_login_verificar(p_documento text, p_nascimento date)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_doc text := regexp_replace(coalesce(p_documento, ''), '[^0-9]', '', 'g'); t public.portal_login_tentativas%rowtype; pe public.pessoas%rowtype;
begin
  if v_doc = '' then return jsonb_build_object('ok', false, 'msg', 'Informe o CPF ou CNPJ.'); end if;
  select * into t from public.portal_login_tentativas where documento = v_doc;
  if found and t.bloqueado_ate is not null and t.bloqueado_ate > now() then
    return jsonb_build_object('ok', false, 'msg', 'Muitas tentativas. Aguarde ' || greatest(1, ceil(extract(epoch from (t.bloqueado_ate - now())) / 60))::int || ' minuto(s).');
  end if;
  select * into pe from public.pessoas where documento = v_doc and ativo and data_nascimento = p_nascimento
     and exists (select 1 from public.contratos c where c.pessoa_id = pessoas.id and c.status <> 'encerrado') limit 1;
  if not found then
    insert into public.portal_login_tentativas (documento, tentativas, bloqueado_ate)
    values (v_doc, 1, null)
    on conflict (documento) do update set tentativas = case when public.portal_login_tentativas.atualizado_em < now() - interval '15 minutes' then 1 else public.portal_login_tentativas.tentativas + 1 end,
      bloqueado_ate = case when (case when public.portal_login_tentativas.atualizado_em < now() - interval '15 minutes' then 1 else public.portal_login_tentativas.tentativas + 1 end) >= 5 then now() + interval '15 minutes' end,
      atualizado_em = now();
    select * into t from public.portal_login_tentativas where documento = v_doc;
    if t.bloqueado_ate is not null and t.bloqueado_ate > now() then
      return jsonb_build_object('ok', false, 'msg', 'Muitas tentativas. Aguarde 15 minuto(s).');
    end if;
    if exists (select 1 from public.pessoas where documento = v_doc and ativo and data_nascimento = p_nascimento) then
      return jsonb_build_object('ok', false, 'msg', 'Nenhum contrato ativo encontrado. Se você se cadastrou recentemente, fale com o provedor para ativar seu acesso.');
    end if;
    return jsonb_build_object('ok', false, 'msg', 'CPF/CNPJ ou data de nascimento não conferem.');
  end if;
  delete from public.portal_login_tentativas where documento = v_doc;
  return jsonb_build_object('ok', true, 'pessoa_id', pe.id, 'organizacao_id', pe.organizacao_id, 'nome', pe.nome, 'email', pe.email);
end; $$;

-- Vincula (ou confirma) o usuário técnico criado pela Edge Function à pessoa
create or replace function public.portal_vincular_servico(p_pessoa_id uuid, p_usuario_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.portal_acessos%rowtype; pe public.pessoas%rowtype;
begin
  select * into pe from public.pessoas where id = p_pessoa_id;
  if not found then raise exception 'Pessoa inválida.' using errcode = 'check_violation'; end if;
  select * into a from public.portal_acessos where pessoa_id = p_pessoa_id;
  if found then
    if a.usuario_id <> p_usuario_id then raise exception 'Pessoa já vinculada a outro login.' using errcode = 'check_violation'; end if;
  else
    insert into public.portal_acessos (organizacao_id, pessoa_id, usuario_id, codigo_indicacao)
    values (pe.organizacao_id, p_pessoa_id, p_usuario_id, public.gerar_codigo_indicacao()) returning * into a;
  end if;
  return jsonb_build_object('pessoa_id', a.pessoa_id, 'codigo_indicacao', a.codigo_indicacao);
end; $$;

-- -----------------------------------------------------------------------------
-- Portal (cliente)
-- -----------------------------------------------------------------------------
create or replace function public.portal_status_rede()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('negocio_id', s.negocio_id, 'negocio', n.nome, 'status', s.status, 'titulo', s.titulo, 'descricao', s.descricao, 'atualizado_em', s.atualizado_em)), '[]'::jsonb)
    from public.portal_status_rede s join public.negocios n on n.id = s.negocio_id
   where s.status <> 'ok' and s.negocio_id in (select negocio_id from public.contratos where pessoa_id = public.portal_pessoa() and status <> 'encerrado'); $$;

create or replace function public.portal_fidelidade()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.fidelidade_cartao(c.id, current_date) || jsonb_build_object('codigo', c.codigo, 'negocio', n.nome, 'plano', pl.nome, 'valor', c.valor, 'ativa', coalesce(pc.fidelidade_ativa, false)) order by c.codigo), '[]'::jsonb)
    from public.contratos c join public.negocios n on n.id = c.negocio_id join public.planos pl on pl.id = c.plano_id
    left join public.portal_config pc on pc.negocio_id = c.negocio_id
   where c.pessoa_id = public.portal_pessoa() and c.status = 'ativo' and c.periodicidade = 'mensal'; $$;

create or replace function public.portal_atualizar_contato(p_email text, p_telefone text, p_receber_avisos boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_pe uuid := public.portal_pessoa(); v_tel text; v_email text;
begin
  if v_pe is null then raise exception 'Acesso ao portal não vinculado.' using errcode = 'insufficient_privilege'; end if;
  v_tel := nullif(regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g'), '');
  v_email := nullif(lower(btrim(coalesce(p_email, ''))), '');
  if v_tel is null or v_tel !~ '^[0-9]{10,13}$' then raise exception 'Informe um telefone válido com DDD.' using errcode = 'check_violation'; end if;
  update public.pessoas set email = v_email, telefone = v_tel, receber_avisos = coalesce(p_receber_avisos, true) where id = v_pe;
  return jsonb_build_object('ok', true, 'email', v_email, 'telefone', v_tel);
end; $$;

create or replace function public.portal_solicitar(p_negocio_id uuid, p_tipo text, p_descricao text default null, p_contrato_id uuid default null)
returns public.portal_solicitacoes
language plpgsql security definer set search_path = public as $$
declare v_pe uuid := public.portal_pessoa(); n public.negocios%rowtype; s public.portal_solicitacoes%rowtype;
begin
  if v_pe is null then raise exception 'Acesso ao portal não vinculado.' using errcode = 'insufficient_privilege'; end if;
  select * into n from public.negocios where id = p_negocio_id;
  if not found or not exists (select 1 from public.contratos where pessoa_id = v_pe and negocio_id = p_negocio_id) then
    raise exception 'Negócio inválido para este cliente.' using errcode = 'check_violation';
  end if;
  if p_contrato_id is not null and not exists (select 1 from public.contratos where id = p_contrato_id and pessoa_id = v_pe) then
    raise exception 'Contrato inválido.' using errcode = 'check_violation';
  end if;
  if (select count(*) from public.portal_solicitacoes where pessoa_id = v_pe and criado_em > now() - interval '1 day') >= 10 then
    raise exception 'Limite de solicitações por dia atingido.' using errcode = 'check_violation';
  end if;
  insert into public.portal_solicitacoes (organizacao_id, negocio_id, pessoa_id, contrato_id, tipo, descricao, protocolo)
  values (n.organizacao_id, p_negocio_id, v_pe, p_contrato_id, p_tipo::public.tipo_solicitacao, nullif(btrim(coalesce(p_descricao, '')), ''),
          'PT-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substr(md5(random()::text), 1, 4)))
  returning * into s;
  return s;
end; $$;

create or replace function public.portal_solicitacoes_cliente()
returns table (id uuid, negocio text, tipo public.tipo_solicitacao, descricao text, protocolo text, status public.status_solicitacao, resposta text, criado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select s.id, n.nome, s.tipo, s.descricao, s.protocolo, s.status, s.resposta, s.criado_em
    from public.portal_solicitacoes s join public.negocios n on n.id = s.negocio_id
   where s.pessoa_id = public.portal_pessoa() order by s.criado_em desc; $$;

-- Faturas do cliente passam a mostrar o mês grátis (cobrança cancelada por desconto integral)
create or replace function public.portal_faturas()
returns table (id uuid, negocio text, contrato_codigo integer, plano text, descricao text, valor numeric, data_vencimento date, data_efetivacao date, status public.status_lancamento, situacao text, observacao text, chave_pix text, instrucoes_pagamento text)
language sql stable security definer set search_path = public as $$
  select l.id, n.nome, c.codigo, pl.nome, l.descricao, l.valor, l.data_vencimento, l.data_efetivacao, l.status,
         case when l.status = 'cancelado' then 'gratis' else public.portal_situacao(l.status, l.data_vencimento) end, l.observacao, pc.chave_pix, pc.instrucoes_pagamento
    from public.lancamentos l
    join public.contratos c on c.id = l.contrato_id
    join public.negocios n on n.id = c.negocio_id
    join public.planos pl on pl.id = c.plano_id
    left join public.portal_config pc on pc.negocio_id = n.id
   where l.pessoa_id = public.portal_pessoa() and l.tipo = 'receita' and (l.status <> 'cancelado' or l.motivo_cancelamento like 'Mês grátis%')
   order by l.data_vencimento desc; $$;

-- Resumo passa a incluir data de nascimento cadastrada (para a tela "meus dados") e whatsapp de suporte
create or replace function public.portal_resumo()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_pe uuid := public.portal_pessoa(); pe public.pessoas%rowtype; a public.portal_acessos%rowtype;
begin
  if v_pe is null then return null; end if;
  select * into pe from public.pessoas where id = v_pe;
  select * into a from public.portal_acessos where pessoa_id = v_pe;
  return jsonb_build_object(
    'pessoa', jsonb_build_object('id', pe.id, 'nome', pe.nome, 'documento', pe.documento, 'email', pe.email, 'telefone', pe.telefone, 'receber_avisos', pe.receber_avisos, 'tem_nascimento', pe.data_nascimento is not null),
    'codigo_indicacao', a.codigo_indicacao,
    'negocios', (select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'nome', n.nome, 'portal', to_jsonb(pc) - 'organizacao_id' - 'id' - 'criado_em' - 'atualizado_em') order by n.nome), '[]'::jsonb)
                   from public.negocios n left join public.portal_config pc on pc.negocio_id = n.id
                  where n.id in (select negocio_id from public.contratos where pessoa_id = v_pe)),
    'em_aberto', (select coalesce(sum(l.valor), 0) from public.lancamentos l where l.pessoa_id = v_pe and l.tipo = 'receita' and l.contrato_id is not null and l.status = 'previsto'),
    'vencidas', (select count(*) from public.lancamentos l where l.pessoa_id = v_pe and l.tipo = 'receita' and l.contrato_id is not null and l.status = 'previsto' and l.data_vencimento < current_date),
    'proximo_vencimento', (select min(l.data_vencimento) from public.lancamentos l where l.pessoa_id = v_pe and l.tipo = 'receita' and l.contrato_id is not null and l.status = 'previsto' and l.data_vencimento >= current_date),
    'contratos_ativos', (select count(*) from public.contratos c where c.pessoa_id = v_pe and c.status = 'ativo'),
    'indicacoes_convertidas', (select count(*) from public.indicacoes i where i.indicador_pessoa_id = v_pe and i.status = 'convertida')
  );
end; $$;

-- Admin: view de solicitações
create view public.vw_portal_solicitacoes
with (security_invoker = true) as
select s.*, pe.nome as pessoa, n.nome as negocio from public.portal_solicitacoes s join public.pessoas pe on pe.id = s.pessoa_id join public.negocios n on n.id = s.negocio_id;

-- -----------------------------------------------------------------------------
-- RLS e permissões
-- -----------------------------------------------------------------------------
alter table public.portal_status_rede enable row level security;
alter table public.portal_solicitacoes enable row level security;
alter table public.portal_login_tentativas enable row level security;
create policy portal_status_rede_select on public.portal_status_rede for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy portal_status_rede_insert on public.portal_status_rede for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy portal_status_rede_update on public.portal_status_rede for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy portal_login_tentativas_bloqueio on public.portal_login_tentativas for select to authenticated using (false);  -- tabela interna: só service_role
create policy portal_solicitacoes_select on public.portal_solicitacoes for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy portal_solicitacoes_update on public.portal_solicitacoes for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.portal_status_rede, public.portal_solicitacoes, public.portal_login_tentativas from public, anon, authenticated;
grant select, insert, update on public.portal_status_rede to authenticated;
grant select, update on public.portal_solicitacoes to authenticated;
grant select on public.vw_portal_solicitacoes to authenticated;
revoke all on function public.fidelidade_cartao(uuid, date), public.fidelidade_registrar_premio(uuid, date) from public, anon, authenticated;
grant execute on function public.fidelidade_cartao(uuid, date) to authenticated;  -- administrador consulta o cartão (RLS de contratos limita à organização)
revoke all on function public.portal_login_verificar(text, date), public.portal_vincular_servico(uuid, uuid) from public, anon, authenticated;
grant execute on function public.portal_login_verificar(text, date), public.portal_vincular_servico(uuid, uuid) to service_role;
revoke all on function public.portal_status_rede(), public.portal_fidelidade(), public.portal_atualizar_contato(text, text, boolean), public.portal_solicitar(uuid, text, text, uuid), public.portal_solicitacoes_cliente() from public, anon;
grant execute on function public.portal_status_rede(), public.portal_fidelidade(), public.portal_atualizar_contato(text, text, boolean), public.portal_solicitar(uuid, text, text, uuid), public.portal_solicitacoes_cliente() to authenticated;
