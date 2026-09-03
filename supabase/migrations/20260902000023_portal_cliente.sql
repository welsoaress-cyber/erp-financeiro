-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0023: PORTAL DO CLIENTE (Etapa 11)
-- Cliente = pessoa existente com um login próprio (auth.users) vinculado em
-- portal_acessos. Ele NÃO é membro de organização: nenhuma policy das tabelas
-- do ERP se aplica a ele. Tudo o que o portal mostra passa por funções
-- portal_* (security definer) filtradas pela pessoa do usuário logado.
-- Novo: portal_config, portal_acessos, promocoes, indicacoes, descontos_contrato.
-- Benefício do Indique e Ganhe = desconto aplicado na próxima cobrança gerada
-- pelo faturamento (descontos_contrato pendentes).
-- =============================================================================

-- 1. Usuário do portal não ganha organização própria
create or replace function public.tg_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_nome text;
begin
  if coalesce(new.raw_user_meta_data ->> 'portal', '') = 'true' then
    return new;  -- cliente do portal: vínculo à pessoa é feito por portal_vincular()
  end if;
  v_nome := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'nome'), ''),
    split_part(coalesce(new.email, ''), '@', 1),
    'Minha organizacao'
  );
  if char_length(v_nome) = 0 then v_nome := 'Minha organizacao'; end if;
  insert into public.organizacoes (nome) values (left(v_nome, 120)) returning id into v_id;
  insert into public.organizacao_membros (organizacao_id, usuario_id, papel) values (v_id, new.id, 'proprietario');
  perform public.criar_categorias_padrao(v_id);
  return new;
end;
$$;

-- 2. Tabelas
create type public.status_indicacao as enum ('pendente', 'convertida', 'cancelada');

create table public.portal_config (
  id                   uuid primary key default gen_random_uuid(),
  organizacao_id       uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id           uuid not null unique references public.negocios (id) on delete restrict,
  ativo                boolean not null default true,
  logo_url             text check (logo_url is null or logo_url ~ '^https://'),
  cor_primaria         text not null default '#1e3a8a' check (cor_primaria ~ '^#[0-9a-fA-F]{6}$'),
  texto_promocional    text check (texto_promocional is null or char_length(texto_promocional) <= 500),
  chave_pix            text check (chave_pix is null or char_length(chave_pix) <= 120),
  instrucoes_pagamento text check (instrucoes_pagamento is null or char_length(instrucoes_pagamento) <= 500),
  beneficio_indicacao  numeric(14,2) not null default 0 check (beneficio_indicacao >= 0),
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now()
);
comment on table public.portal_config is 'Aparência e regras do portal por negócio. beneficio_indicacao = desconto (R$) na próxima fatura do indicador por indicação convertida.';

create table public.portal_acessos (
  id               uuid primary key default gen_random_uuid(),
  organizacao_id   uuid not null references public.organizacoes (id) on delete restrict,
  pessoa_id        uuid not null unique references public.pessoas (id) on delete restrict,
  usuario_id       uuid not null unique references auth.users (id) on delete cascade,
  codigo_indicacao text not null unique check (codigo_indicacao ~ '^[A-Z0-9]{8}$'),
  criado_em        timestamptz not null default now()
);
comment on table public.portal_acessos is 'Login do portal (auth.users) ↔ pessoa. Um login por pessoa. Código de indicação único.';

create table public.promocoes (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  plano_id       uuid references public.planos (id) on delete restrict,
  titulo         text not null check (char_length(btrim(titulo)) between 3 and 100),
  descricao      text not null check (char_length(descricao) between 3 and 1000),
  regras         text check (regras is null or char_length(regras) <= 1000),
  como_aderir    text check (como_aderir is null or char_length(como_aderir) <= 500),
  data_inicio    date not null default current_date,
  data_fim       date,
  ativa          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  check (data_fim is null or data_fim >= data_inicio)
);
create index promocoes_negocio_idx on public.promocoes (negocio_id, ativa);
comment on table public.promocoes is 'Promoções por negócio; plano_id restringe a clientes daquele plano.';

create table public.indicacoes (
  id                  uuid primary key default gen_random_uuid(),
  organizacao_id      uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id          uuid not null references public.negocios (id) on delete restrict,
  indicador_pessoa_id uuid not null references public.pessoas (id) on delete restrict,
  nome_indicado       text not null check (char_length(btrim(nome_indicado)) between 2 and 120),
  telefone_indicado   text not null check (telefone_indicado ~ '^[0-9]{10,13}$'),
  indicado_pessoa_id  uuid references public.pessoas (id) on delete restrict,
  status              public.status_indicacao not null default 'pendente',
  beneficio_valor     numeric(14,2) not null default 0 check (beneficio_valor >= 0),
  desconto_id         uuid,
  observacao          text check (observacao is null or char_length(observacao) <= 300),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  check ((status = 'convertida') = (indicado_pessoa_id is not null))
);
create index indicacoes_indicador_idx on public.indicacoes (indicador_pessoa_id, criado_em desc);
create index indicacoes_negocio_status_idx on public.indicacoes (negocio_id, status);
comment on table public.indicacoes is 'Indique e Ganhe: quem indicou, quem foi indicado, status e benefício.';

create table public.descontos_contrato (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  contrato_id    uuid not null references public.contratos (id) on delete restrict,
  valor          numeric(14,2) not null check (valor > 0),
  motivo         text not null check (char_length(motivo) between 3 and 200),
  indicacao_id   uuid references public.indicacoes (id) on delete restrict,
  lancamento_id  uuid references public.lancamentos (id) on delete restrict,
  criado_em      timestamptz not null default now()
);
create index descontos_contrato_pendentes_idx on public.descontos_contrato (contrato_id) where lancamento_id is null;
comment on table public.descontos_contrato is 'Descontos a aplicar na próxima cobrança gerada pelo faturamento. lancamento_id preenchido = já aplicado.';

-- 3. Proteções e auditoria
create or replace function public.tg_portal_config_protecao()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id) then
    raise exception 'A configuração do portal não pode mudar de negócio.' using errcode = 'check_violation';
  end if;
  perform public.validar_negocio(new.negocio_id, new.organizacao_id, tg_op = 'INSERT');
  return new;
end; $$;
create trigger portal_config_protecao before insert or update on public.portal_config for each row execute function public.tg_portal_config_protecao();
create trigger portal_config_atualizado_em before update on public.portal_config for each row execute function public.tg_atualizado_em();
create trigger portal_config_auditoria after insert or update or delete on public.portal_config for each row execute function public.tg_auditoria();

create or replace function public.tg_promocoes_protecao()
returns trigger language plpgsql set search_path = public as $$
declare pl public.planos%rowtype;
begin
  if tg_op = 'UPDATE' and (new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id) then
    raise exception 'A promoção não pode mudar de negócio.' using errcode = 'check_violation';
  end if;
  perform public.validar_negocio(new.negocio_id, new.organizacao_id, tg_op = 'INSERT');
  if new.plano_id is not null then
    select * into pl from public.planos where id = new.plano_id;
    if not found or pl.negocio_id <> new.negocio_id then raise exception 'O plano da promoção deve ser do mesmo negócio.' using errcode = 'check_violation'; end if;
  end if;
  new.titulo := btrim(new.titulo);
  return new;
end; $$;
create trigger promocoes_protecao before insert or update on public.promocoes for each row execute function public.tg_promocoes_protecao();
create trigger promocoes_atualizado_em before update on public.promocoes for each row execute function public.tg_atualizado_em();
create trigger promocoes_auditoria after insert or update or delete on public.promocoes for each row execute function public.tg_auditoria();

create or replace function public.tg_indicacoes_protecao()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.indicador_pessoa_id <> old.indicador_pessoa_id or new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id then
      raise exception 'Indicador e negócio da indicação não mudam.' using errcode = 'check_violation';
    end if;
    if old.status = 'convertida' and new.status <> 'convertida' then
      raise exception 'Indicação convertida não volta atrás.' using errcode = 'check_violation';
    end if;
    if new.status = 'convertida' and old.status <> 'convertida' and not public.motor_ativo() then
      raise exception 'Use converter_indicacao() para converter.' using errcode = 'check_violation';
    end if;
  end if;
  new.nome_indicado := btrim(new.nome_indicado);
  new.telefone_indicado := regexp_replace(new.telefone_indicado, '[^0-9]', '', 'g');
  return new;
end; $$;
create trigger indicacoes_protecao before insert or update on public.indicacoes for each row execute function public.tg_indicacoes_protecao();
create trigger indicacoes_atualizado_em before update on public.indicacoes for each row execute function public.tg_atualizado_em();
create trigger indicacoes_auditoria after insert or update or delete on public.indicacoes for each row execute function public.tg_auditoria();

create or replace function public.tg_descontos_protecao()
returns trigger language plpgsql set search_path = public as $$
begin
  if not public.motor_ativo() then
    raise exception 'Descontos são gravados pelo motor (converter_indicacao / faturamento).' using errcode = 'insufficient_privilege';
  end if;
  if tg_op = 'UPDATE' and old.lancamento_id is not null then
    raise exception 'Desconto já aplicado não muda.' using errcode = 'check_violation';
  end if;
  return new;
end; $$;
create trigger descontos_protecao before insert or update or delete on public.descontos_contrato for each row execute function public.tg_descontos_protecao();
create trigger descontos_auditoria after insert or update or delete on public.descontos_contrato for each row execute function public.tg_auditoria();
create trigger portal_acessos_auditoria after insert or update or delete on public.portal_acessos for each row execute function public.tg_auditoria();

-- 4. Faturamento aplica descontos pendentes na próxima cobrança do contrato
create or replace function public.faturar_contrato(p_contrato uuid, p_ate date, out gerados integer, out pendencia text)
language plpgsql
set search_path = public
as $$
declare
  c public.contratos%rowtype;
  n public.negocios%rowtype;
  pl public.planos%rowtype;
  v_conta uuid; v_cat uuid; v_comp date; v_venc date; l public.lancamentos%rowtype;
  v_desc numeric(14,2); v_valor numeric(14,2);
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
    select coalesce(sum(d.valor), 0) into v_desc from public.descontos_contrato d where d.contrato_id = c.id and d.lancamento_id is null;
    v_valor := greatest(c.valor - v_desc, 0.01);
    insert into public.lancamentos (
      organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
      conta_id, categoria_id, origem, negocio_id, pessoa_id, contrato_id, observacao
    ) values (
      c.organizacao_id, 'receita',
      left(pl.nome || ' · ' || to_char(v_comp, 'MM/YYYY') || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140),
      v_valor, v_venc, v_venc, null, 'previsto',
      v_conta, v_cat, 'faturamento', c.negocio_id, c.pessoa_id, c.id,
      case when v_desc > 0 then 'Desconto aplicado: ' || public.moeda_br(least(v_desc, c.valor - 0.01)) || ' (Indique e Ganhe / outros).' end
    ) returning * into l;
    if v_desc > 0 then
      update public.descontos_contrato set lancamento_id = l.id where contrato_id = c.id and lancamento_id is null;
    end if;
    insert into public.faturamentos (organizacao_id, contrato_id, competencia, lancamento_id) values (c.organizacao_id, c.id, v_comp, l.id);
    gerados := gerados + 1;
  end loop;
end;
$$;

-- 5. Portal: helpers e funções (security definer, filtradas pela pessoa do login)
create or replace function public.portal_pessoa()
returns uuid
language sql
stable
security definer
set search_path = public
as $$ select pessoa_id from public.portal_acessos where usuario_id = auth.uid(); $$;

create or replace function public.gerar_codigo_indicacao()
returns text
language plpgsql
set search_path = public
as $$
declare v text; alfabeto text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  loop
    v := '';
    for i in 1..8 loop v := v || substr(alfabeto, 1 + floor(random() * length(alfabeto))::int, 1); end loop;
    exit when not exists (select 1 from public.portal_acessos where codigo_indicacao = v);
  end loop;
  return v;
end; $$;

-- Vincula o usuário logado (cadastrado com metadata portal=true) a uma pessoa pelo CPF/CNPJ + telefone.
create or replace function public.portal_vincular(p_documento text, p_telefone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_doc text; v_tel text; pe public.pessoas%rowtype; a public.portal_acessos%rowtype; n int;
begin
  if auth.uid() is null then raise exception 'Não autenticado.' using errcode = 'insufficient_privilege'; end if;
  if exists (select 1 from public.portal_acessos where usuario_id = auth.uid()) then
    select * into a from public.portal_acessos where usuario_id = auth.uid();
    return jsonb_build_object('pessoa_id', a.pessoa_id, 'codigo_indicacao', a.codigo_indicacao, 'ja_vinculado', true);
  end if;
  if exists (select 1 from public.organizacao_membros where usuario_id = auth.uid()) then
    raise exception 'Este login é de administrador, não de cliente.' using errcode = 'check_violation';
  end if;
  v_doc := nullif(regexp_replace(coalesce(p_documento, ''), '[^0-9]', '', 'g'), '');
  v_tel := nullif(regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g'), '');
  if v_doc is null or v_tel is null then raise exception 'Informe CPF/CNPJ e telefone.' using errcode = 'check_violation'; end if;
  select count(*) into n from public.pessoas where documento = v_doc and ativo;
  if n = 0 then raise exception 'Cadastro não encontrado. Confira o CPF/CNPJ ou fale com o provedor.' using errcode = 'check_violation'; end if;
  select * into pe from public.pessoas where documento = v_doc and ativo and telefone is not null and right(telefone, 8) = right(v_tel, 8) limit 1;
  if not found then raise exception 'O telefone não confere com o cadastro. Fale com o provedor.' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.portal_acessos where pessoa_id = pe.id) then
    raise exception 'Já existe um acesso ao portal para este cadastro. Use "Esqueci a senha".' using errcode = 'check_violation';
  end if;
  insert into public.portal_acessos (organizacao_id, pessoa_id, usuario_id, codigo_indicacao)
  values (pe.organizacao_id, pe.id, auth.uid(), public.gerar_codigo_indicacao()) returning * into a;
  return jsonb_build_object('pessoa_id', a.pessoa_id, 'codigo_indicacao', a.codigo_indicacao, 'ja_vinculado', false);
end; $$;

-- Situação de uma cobrança para o cliente
create or replace function public.portal_situacao(p_status public.status_lancamento, p_venc date)
returns text language sql immutable set search_path = public as $$
  select case when p_status = 'efetivado' then 'paga' when p_status = 'cancelado' then 'cancelada'
              when p_venc < current_date then 'vencida' else 'pendente' end; $$;

-- Resumo do painel
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
    'pessoa', jsonb_build_object('id', pe.id, 'nome', pe.nome, 'documento', pe.documento, 'email', pe.email, 'telefone', pe.telefone, 'receber_avisos', pe.receber_avisos),
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

-- Faturas emitidas (cobranças de contrato) — só do cliente
create or replace function public.portal_faturas()
returns table (id uuid, negocio text, contrato_codigo integer, plano text, descricao text, valor numeric, data_vencimento date, data_efetivacao date,
               status public.status_lancamento, situacao text, observacao text, chave_pix text, instrucoes_pagamento text)
language sql stable security definer set search_path = public as $$
  select l.id, n.nome, c.codigo, pl.nome, l.descricao, l.valor, l.data_vencimento, l.data_efetivacao, l.status,
         public.portal_situacao(l.status, l.data_vencimento), l.observacao, pc.chave_pix, pc.instrucoes_pagamento
    from public.lancamentos l
    join public.contratos c on c.id = l.contrato_id
    join public.negocios n on n.id = c.negocio_id
    join public.planos pl on pl.id = c.plano_id
    left join public.portal_config pc on pc.negocio_id = n.id
   where l.pessoa_id = public.portal_pessoa() and l.tipo = 'receita' and l.status <> 'cancelado'
   order by l.data_vencimento desc; $$;

-- Próximas cobranças previstas pelo faturamento (até 6 meses), sem gravar nada
create or replace function public.portal_proximas_faturas()
returns table (contrato_codigo integer, negocio text, plano text, competencia date, data_vencimento date, valor numeric, prevista boolean)
language sql stable security definer set search_path = public as $$
  select c.codigo, n.nome, pl.nome, comp, public.data_vencimento_no_mes(comp, c.dia_vencimento),
         greatest(c.valor - coalesce((select sum(d.valor) from public.descontos_contrato d where d.contrato_id = c.id and d.lancamento_id is null), 0), 0.01),
         true
    from public.contratos c
    join public.negocios n on n.id = c.negocio_id
    join public.planos pl on pl.id = c.plano_id
    cross join lateral public.competencias_pendentes(c.id, (current_date + interval '6 months')::date) as comp
   where c.pessoa_id = public.portal_pessoa() and c.status = 'ativo' and c.faturamento_automatico
   order by 5; $$;

-- Pagamentos realizados
create or replace function public.portal_pagamentos()
returns table (id uuid, data_pagamento date, valor numeric, descricao text, negocio text, contrato_codigo integer, forma text)
language sql stable security definer set search_path = public as $$
  select l.id, l.data_efetivacao, l.valor, l.descricao, n.nome, c.codigo, ct.nome
    from public.lancamentos l
    join public.contratos c on c.id = l.contrato_id
    join public.negocios n on n.id = c.negocio_id
    join public.contas ct on ct.id = l.conta_id
   where l.pessoa_id = public.portal_pessoa() and l.tipo = 'receita' and l.status = 'efetivado'
   order by l.data_efetivacao desc; $$;

-- Contratos do cliente
create or replace function public.portal_contratos()
returns table (id uuid, codigo integer, negocio text, plano text, plano_descricao text, valor numeric, periodicidade public.periodicidade,
               data_inicio date, data_fim date, dia_vencimento smallint, status public.status_contrato, proxima_renovacao date, descontos_pendentes numeric)
language sql stable security definer set search_path = public as $$
  select c.id, c.codigo, n.nome, pl.nome, pl.descricao, c.valor, c.periodicidade, c.data_inicio, c.data_fim, c.dia_vencimento, c.status,
         (select min(comp) from public.competencias_pendentes(c.id, (current_date + interval '12 months')::date) comp),
         coalesce((select sum(d.valor) from public.descontos_contrato d where d.contrato_id = c.id and d.lancamento_id is null), 0)
    from public.contratos c
    join public.negocios n on n.id = c.negocio_id
    join public.planos pl on pl.id = c.plano_id
   where c.pessoa_id = public.portal_pessoa()
   order by c.status = 'ativo' desc, c.data_inicio desc; $$;

-- Promoções vigentes dos negócios do cliente (todas ou do plano dele)
create or replace function public.portal_promocoes()
returns table (id uuid, negocio text, titulo text, descricao text, regras text, como_aderir text, data_inicio date, data_fim date, plano text)
language sql stable security definer set search_path = public as $$
  select p.id, n.nome, p.titulo, p.descricao, p.regras, p.como_aderir, p.data_inicio, p.data_fim, pl.nome
    from public.promocoes p
    join public.negocios n on n.id = p.negocio_id
    left join public.planos pl on pl.id = p.plano_id
   where p.ativa and p.data_inicio <= current_date and (p.data_fim is null or p.data_fim >= current_date)
     and n.id in (select negocio_id from public.contratos where pessoa_id = public.portal_pessoa())
     and (p.plano_id is null or p.plano_id in (select plano_id from public.contratos where pessoa_id = public.portal_pessoa() and status = 'ativo'))
   order by p.data_inicio desc; $$;

-- Indicações do cliente
create or replace function public.portal_indicacoes()
returns table (id uuid, negocio text, nome_indicado text, status public.status_indicacao, beneficio_valor numeric, criado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select i.id, n.nome, i.nome_indicado, i.status, i.beneficio_valor, i.criado_em
    from public.indicacoes i join public.negocios n on n.id = i.negocio_id
   where i.indicador_pessoa_id = public.portal_pessoa()
   order by i.criado_em desc; $$;

-- Indicação enviada pelo próprio cliente (logado) para um negócio dele
create or replace function public.portal_indicar(p_negocio_id uuid, p_nome text, p_telefone text)
returns public.indicacoes
language plpgsql security definer set search_path = public as $$
declare v_pe uuid := public.portal_pessoa(); i public.indicacoes%rowtype; n public.negocios%rowtype; v_tel text;
begin
  if v_pe is null then raise exception 'Acesso ao portal não vinculado.' using errcode = 'insufficient_privilege'; end if;
  select * into n from public.negocios where id = p_negocio_id;
  if not found or not exists (select 1 from public.contratos where pessoa_id = v_pe and negocio_id = p_negocio_id) then
    raise exception 'Negócio inválido para este cliente.' using errcode = 'check_violation';
  end if;
  v_tel := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  if exists (select 1 from public.indicacoes where indicador_pessoa_id = v_pe and telefone_indicado = v_tel and status <> 'cancelada') then
    raise exception 'Você já indicou este telefone.' using errcode = 'check_violation';
  end if;
  if (select count(*) from public.indicacoes where indicador_pessoa_id = v_pe and criado_em > now() - interval '1 day') >= 20 then
    raise exception 'Limite de indicações por dia atingido.' using errcode = 'check_violation';
  end if;
  insert into public.indicacoes (organizacao_id, negocio_id, indicador_pessoa_id, nome_indicado, telefone_indicado)
  values (n.organizacao_id, p_negocio_id, v_pe, p_nome, v_tel) returning * into i;
  return i;
end; $$;

-- Página pública do link de indicação (anon): quem chega pelo link deixa nome e telefone
create or replace function public.portal_indicacao_publica(p_codigo text, p_nome text, p_telefone text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.portal_acessos%rowtype; v_neg uuid; n public.negocios%rowtype; v_tel text;
begin
  select * into a from public.portal_acessos where codigo_indicacao = upper(btrim(coalesce(p_codigo, '')));
  if not found then raise exception 'Link de indicação inválido.' using errcode = 'check_violation'; end if;
  select c.negocio_id into v_neg from public.contratos c where c.pessoa_id = a.pessoa_id and c.status = 'ativo' order by c.data_inicio desc limit 1;
  if v_neg is null then raise exception 'Este link não está mais ativo.' using errcode = 'check_violation'; end if;
  select * into n from public.negocios where id = v_neg;
  v_tel := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  if exists (select 1 from public.indicacoes where indicador_pessoa_id = a.pessoa_id and telefone_indicado = v_tel and status <> 'cancelada') then
    return jsonb_build_object('ok', true, 'negocio', n.nome, 'repetida', true);
  end if;
  if (select count(*) from public.indicacoes where indicador_pessoa_id = a.pessoa_id and criado_em > now() - interval '1 day') >= 20 then
    raise exception 'Limite de indicações atingido. Tente amanhã.' using errcode = 'check_violation';
  end if;
  insert into public.indicacoes (organizacao_id, negocio_id, indicador_pessoa_id, nome_indicado, telefone_indicado)
  values (n.organizacao_id, v_neg, a.pessoa_id, p_nome, v_tel);
  return jsonb_build_object('ok', true, 'negocio', n.nome, 'repetida', false);
end; $$;

-- Nome do negócio para a página pública do link (sem dados do cliente)
create or replace function public.portal_info_indicacao(p_codigo text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('negocio', n.nome, 'texto', pc.texto_promocional, 'cor', coalesce(pc.cor_primaria, '#1e3a8a'), 'logo', pc.logo_url,
                            'indicador', split_part(pe.nome, ' ', 1))
    from public.portal_acessos a
    join public.pessoas pe on pe.id = a.pessoa_id
    join public.contratos c on c.pessoa_id = a.pessoa_id and c.status = 'ativo'
    join public.negocios n on n.id = c.negocio_id
    left join public.portal_config pc on pc.negocio_id = n.id
   where a.codigo_indicacao = upper(btrim(coalesce(p_codigo, '')))
   order by c.data_inicio desc limit 1; $$;

-- Administrador: converter indicação (cliente indicado virou pessoa com contrato) e aplicar benefício ao indicador
create or replace function public.converter_indicacao(p_indicacao_id uuid, p_indicado_pessoa_id uuid)
returns public.indicacoes
language plpgsql security definer set search_path = public as $$
declare i public.indicacoes%rowtype; pc public.portal_config%rowtype; v_contrato uuid; v_desc uuid;
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
  perform set_config('erp.motor', 'on', true);
  if pc.beneficio_indicacao > 0 then
    select c.id into v_contrato from public.contratos c where c.pessoa_id = i.indicador_pessoa_id and c.negocio_id = i.negocio_id and c.status = 'ativo' order by c.data_inicio desc limit 1;
    if v_contrato is not null then
      insert into public.descontos_contrato (organizacao_id, contrato_id, valor, motivo, indicacao_id)
      values (i.organizacao_id, v_contrato, pc.beneficio_indicacao, 'Indique e Ganhe: indicação de ' || i.nome_indicado, i.id) returning id into v_desc;
    end if;
  end if;
  update public.indicacoes set status = 'convertida', indicado_pessoa_id = p_indicado_pessoa_id,
         beneficio_valor = case when v_desc is null then 0 else pc.beneficio_indicacao end, desconto_id = v_desc
   where id = i.id returning * into i;
  return i;
end; $$;

-- Administrador: lista de acessos do portal (quem já tem login)
create view public.vw_portal_acessos
with (security_invoker = true) as
select a.id, a.organizacao_id, a.pessoa_id, pe.nome as pessoa, a.codigo_indicacao, a.criado_em,
       (select count(*) from public.indicacoes i where i.indicador_pessoa_id = a.pessoa_id) as indicacoes
  from public.portal_acessos a join public.pessoas pe on pe.id = a.pessoa_id;

-- 6. RLS e permissões
alter table public.portal_config enable row level security;
alter table public.portal_acessos enable row level security;
alter table public.promocoes enable row level security;
alter table public.indicacoes enable row level security;
alter table public.descontos_contrato enable row level security;
create policy portal_config_select on public.portal_config for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy portal_config_insert on public.portal_config for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy portal_config_update on public.portal_config for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy portal_acessos_select on public.portal_acessos for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()) or usuario_id = auth.uid());
create policy promocoes_select on public.promocoes for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy promocoes_insert on public.promocoes for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy promocoes_update on public.promocoes for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy indicacoes_select on public.indicacoes for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy indicacoes_update on public.indicacoes for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy descontos_select on public.descontos_contrato for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.portal_config, public.portal_acessos, public.promocoes, public.indicacoes, public.descontos_contrato from public, anon, authenticated;
grant select, insert, update on public.portal_config, public.promocoes to authenticated;
grant select, update on public.indicacoes to authenticated;
grant select on public.portal_acessos, public.descontos_contrato, public.vw_portal_acessos to authenticated;
revoke all on function public.tg_portal_config_protecao(), public.tg_promocoes_protecao(), public.tg_indicacoes_protecao(), public.tg_descontos_protecao(), public.gerar_codigo_indicacao() from public, anon, authenticated;
revoke all on function public.portal_pessoa(), public.portal_vincular(text, text), public.portal_resumo(), public.portal_faturas(), public.portal_proximas_faturas(),
  public.portal_pagamentos(), public.portal_contratos(), public.portal_promocoes(), public.portal_indicacoes(), public.portal_indicar(uuid, text, text),
  public.converter_indicacao(uuid, uuid), public.portal_situacao(public.status_lancamento, date) from public, anon;
grant execute on function public.portal_pessoa(), public.portal_vincular(text, text), public.portal_resumo(), public.portal_faturas(), public.portal_proximas_faturas(),
  public.portal_pagamentos(), public.portal_contratos(), public.portal_promocoes(), public.portal_indicacoes(), public.portal_indicar(uuid, text, text),
  public.converter_indicacao(uuid, uuid), public.portal_situacao(public.status_lancamento, date) to authenticated;
revoke all on function public.portal_indicacao_publica(text, text, text), public.portal_info_indicacao(text) from public;
grant execute on function public.portal_indicacao_publica(text, text, text), public.portal_info_indicacao(text) to anon, authenticated;
