-- =============================================================================
-- 0055 · Etapa 29A — Ordens de Serviço (OS): técnicos, bolsa, chamados e comissão
-- =============================================================================
-- Chamados técnicos do provedor, integrados a pessoas, contratos, negócios,
-- estoque (28A/B), lançamentos e contas a pagar. Decisões do proprietário:
-- - Técnico tem cadastro próprio (login entra na 29B) e vira pessoa (fornecedor
--   das comissões). Bolsa separada do estoque central, com mínimo por item.
-- - Abastecimento transfere do central para a bolsa (origem 'transferencia');
--   devolução volta ao central; perda/avaria exige motivo e NÃO gera cobrança
--   automática do técnico (caso caro é negociado por fora).
-- - Número: OS{contrato 3 díg}{DDMMAAAA}{letra} ou MAN{DDMMAAAA}{letra}.
--   Reabertura é chamado NOVO: {número original}-{letra}.
-- - Tempo conta do horário AGENDADO até o encerramento, menos pausas (pausa por
--   qualquer motivo, com texto obrigatório). Também guarda o tempo real de
--   execução (início→fim). Técnico não vê tempo (app 29B).
-- - Encerramento: materiais saem da bolsa (pode ficar negativa — alerta),
--   diagnóstico padronizado, sinal em dBm. Instalação/mudança com contrato gera
--   registro em estoque_instalacoes (payback 28B) sem tocar o estoque central
--   (já saiu na transferência). Reparo/manutenção com contrato é custo do
--   cliente (view própria); OS sem cliente é custo da rede, sem rateio.
-- - Comissão (instalação/mudança): decisão do admin, valor editável (padrão 50%
--   da mensalidade), despesa prevista no Contas a Pagar na categoria Comissões,
--   fornecedor = pessoa do técnico, vinculada ao chamado (comissao_lancamento_id).
--   O lançamento não leva contrato_id (o motor exige pessoa = pessoa do contrato);
--   no payback a comissão entra pela view, somada ao custo de aquisição.
-- - Retorno: novo chamado do mesmo cliente até 7 dias após um encerramento é
--   marcado como reincidência.
-- Desvio da spec: sem status 'reaberto' (reabertura cria chamado novo, decisão
-- posterior do proprietário); nomes/`criado_em` seguem o padrão do repositório.
-- =============================================================================

create type public.tipo_os as enum ('instalacao', 'manutencao', 'reparo', 'mudanca_endereco', 'rompimento', 'vistoria');
create type public.prioridade_os as enum ('normal', 'urgente');
create type public.status_os as enum ('aberto', 'em_atendimento', 'pausado', 'encerrado', 'cancelado');
create type public.evento_os as enum ('abertura', 'atribuicao', 'ciencia', 'agendamento', 'remarcacao_solicitada', 'remarcacao_respondida', 'inicio', 'pausa', 'retomada', 'encerramento', 'reabertura', 'cancelamento', 'avaliacao', 'comissao');
create type public.origem_abertura_os as enum ('admin', 'portal', 'interno');
create type public.diagnostico_os as enum ('conector', 'cabo_rompido', 'onu_queimada', 'energia_cliente', 'roteador_cliente', 'sinal_degradado', 'sem_defeito', 'outro');
create type public.tipo_mov_tecnico as enum ('abastecimento', 'consumo', 'perda', 'avaria', 'devolucao');
alter type public.origem_movimentacao_estoque add value if not exists 'transferencia';

-- -----------------------------------------------------------------------------
-- Técnicos e bolsa
-- -----------------------------------------------------------------------------
create table public.tecnicos (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  pessoa_id uuid not null references public.pessoas (id), -- fornecedor das comissões
  usuario_id uuid, -- login próprio (29B)
  nome text not null check (char_length(btrim(nome)) between 2 and 80),
  telefone text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (organizacao_id, pessoa_id)
);
create trigger tecnicos_atualizado before update on public.tecnicos for each row execute function public.tg_atualizado_em();

create table public.tecnico_estoque (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  tecnico_id uuid not null references public.tecnicos (id),
  item_id uuid not null references public.estoque_itens (id),
  quantidade numeric(12,2) not null default 0, -- pode ficar negativa (encerrou sem saldo: alerta)
  quantidade_minima numeric(12,2) not null default 0 check (quantidade_minima >= 0),
  atualizado_em timestamptz not null default now(),
  unique (tecnico_id, item_id)
);
create trigger tecnico_estoque_atualizado before update on public.tecnico_estoque for each row execute function public.tg_atualizado_em();

create table public.tecnico_movimentacoes (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  tecnico_id uuid not null references public.tecnicos (id),
  item_id uuid not null references public.estoque_itens (id),
  tipo public.tipo_mov_tecnico not null,
  quantidade numeric(12,2) not null check (quantidade > 0),
  valor_unitario numeric(12,4) not null default 0,
  valor_total numeric(12,2) not null default 0,
  motivo text check (motivo is null or char_length(motivo) <= 300),
  defeito_fabrica boolean not null default false, -- avaria sem responsabilidade do técnico
  os_id uuid, -- fk adicionada após ordens_servico
  usuario_id uuid,
  criado_em timestamptz not null default now(),
  check (tipo not in ('perda', 'avaria') or char_length(btrim(coalesce(motivo, ''))) >= 3)
);
create index tecnico_mov_tecnico on public.tecnico_movimentacoes (tecnico_id, criado_em desc);

-- -----------------------------------------------------------------------------
-- Ordens de serviço
-- -----------------------------------------------------------------------------
create table public.ordens_servico (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  numero text not null,
  os_origem_id uuid references public.ordens_servico (id), -- reabertura
  retorno boolean not null default false, -- reincidência em até 7 dias
  contrato_id uuid references public.contratos (id),
  pessoa_id uuid references public.pessoas (id),
  tecnico_id uuid references public.tecnicos (id),
  cto_id uuid references public.ctos (id), -- rompimento/instalação no mapa
  tipo public.tipo_os not null,
  prioridade public.prioridade_os not null default 'normal',
  status public.status_os not null default 'aberto',
  aberto_via public.origem_abertura_os not null default 'admin',
  descricao text not null check (char_length(btrim(descricao)) between 3 and 500),
  data_agendada date,
  hora_agendada time,
  remarcacao_data date,
  remarcacao_hora time,
  remarcacao_motivo text,
  data_ciencia timestamptz,
  data_inicio timestamptz,
  data_fim timestamptz,
  pausado_em timestamptz,
  tempo_total_minutos integer,
  tempo_pausa_minutos integer not null default 0,
  tempo_execucao_minutos integer,
  diagnostico public.diagnostico_os,
  sinal_dbm numeric(5,1),
  avaliacao_resolvido boolean,
  avaliacao_nota smallint check (avaliacao_nota between 1 and 5),
  comissao_lancamento_id uuid references public.lancamentos (id),
  observacao text check (observacao is null or char_length(observacao) <= 500),
  usuario_abertura uuid,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (organizacao_id, numero),
  check (pessoa_id is not null or contrato_id is null) -- contrato exige cliente
);
create index os_negocio_status on public.ordens_servico (negocio_id, status);
create index os_tecnico on public.ordens_servico (tecnico_id) where tecnico_id is not null;
create index os_pessoa on public.ordens_servico (pessoa_id) where pessoa_id is not null;
create index os_contrato on public.ordens_servico (contrato_id) where contrato_id is not null;
create trigger os_atualizado before update on public.ordens_servico for each row execute function public.tg_atualizado_em();

alter table public.tecnico_movimentacoes add constraint tecnico_mov_os_fk foreign key (os_id) references public.ordens_servico (id);

create table public.os_materiais (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  os_id uuid not null references public.ordens_servico (id),
  item_id uuid not null references public.estoque_itens (id),
  quantidade numeric(12,2) not null check (quantidade > 0),
  valor_unitario numeric(12,4) not null default 0,
  valor_total numeric(12,2) not null default 0,
  criado_em timestamptz not null default now()
);
create index os_materiais_os on public.os_materiais (os_id);

create table public.os_historico (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  os_id uuid not null references public.ordens_servico (id),
  evento public.evento_os not null,
  observacao text check (observacao is null or char_length(observacao) <= 500),
  usuario_id uuid,
  criado_em timestamptz not null default now()
);
create index os_historico_os on public.os_historico (os_id, criado_em);

-- vínculo da instalação (payback 28B) com a OS
alter table public.estoque_instalacoes add column os_id uuid references public.ordens_servico (id);

-- -----------------------------------------------------------------------------
-- Proteção: OS, materiais, histórico, bolsa e movimentações só mudam pelo motor
-- (quantidade_minima da bolsa é a exceção: admin configura direto)
-- -----------------------------------------------------------------------------
create or replace function public.tg_os_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name in ('tecnico_movimentacoes', 'os_materiais', 'os_historico') and tg_op in ('UPDATE', 'DELETE') then
    raise exception 'Registro imutável do módulo de OS.' using errcode = 'check_violation';
  end if;
  if coalesce(current_setting('erp.motor', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  if tg_table_name = 'tecnico_estoque' then
    if tg_op = 'INSERT' and new.quantidade <> 0 then
      raise exception 'A bolsa começa zerada: abasteça pelo estoque central.' using errcode = 'check_violation';
    end if;
    if tg_op = 'UPDATE' and new.quantidade <> old.quantidade then
      raise exception 'A quantidade da bolsa muda só por movimentação (abastecer, consumir, devolver, perda).' using errcode = 'check_violation';
    end if;
    if tg_op = 'DELETE' then
      raise exception 'Item da bolsa não é excluído; zere e desative pelo mínimo.' using errcode = 'check_violation';
    end if;
    return coalesce(new, old);
  end if;
  raise exception 'Operação permitida apenas pelo motor de OS.' using errcode = 'insufficient_privilege';
end;
$$;
revoke all on function public.tg_os_protecao() from public, anon, authenticated;
create trigger os_protecao before insert or update or delete on public.ordens_servico for each row execute function public.tg_os_protecao();
create trigger os_materiais_protecao before insert or update or delete on public.os_materiais for each row execute function public.tg_os_protecao();
create trigger os_historico_protecao before insert or update or delete on public.os_historico for each row execute function public.tg_os_protecao();
create trigger tecnico_mov_protecao before insert or update or delete on public.tecnico_movimentacoes for each row execute function public.tg_os_protecao();
create trigger tecnico_estoque_protecao before insert or update or delete on public.tecnico_estoque for each row execute function public.tg_os_protecao();

-- -----------------------------------------------------------------------------
-- Auxiliares internos
-- -----------------------------------------------------------------------------
create function public.os_registrar_evento(p_os_id uuid, p_evento public.evento_os, p_observacao text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('erp.motor', 'on', true);
  insert into public.os_historico (organizacao_id, os_id, evento, observacao, usuario_id)
  select organizacao_id, id, p_evento, p_observacao, auth.uid() from public.ordens_servico where id = p_os_id;
end;
$$;
revoke all on function public.os_registrar_evento(uuid, public.evento_os, text) from public, anon, authenticated;

-- movimenta a bolsa do técnico (delta pode ser negativo) e devolve o custo médio do item
create function public.os_mover_bolsa(p_tecnico_id uuid, p_item_id uuid, p_delta numeric, p_tipo public.tipo_mov_tecnico, p_motivo text, p_defeito boolean, p_os_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare it public.estoque_itens%rowtype; t public.tecnicos%rowtype;
begin
  select * into t from public.tecnicos where id = p_tecnico_id;
  select * into it from public.estoque_itens where id = p_item_id;
  if it.id is null or it.negocio_id <> t.negocio_id then raise exception 'Item inválido para o negócio do técnico.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  insert into public.tecnico_estoque (organizacao_id, tecnico_id, item_id, quantidade)
  values (t.organizacao_id, p_tecnico_id, p_item_id, 0)
  on conflict (tecnico_id, item_id) do nothing;
  update public.tecnico_estoque set quantidade = quantidade + p_delta where tecnico_id = p_tecnico_id and item_id = p_item_id;
  insert into public.tecnico_movimentacoes (organizacao_id, tecnico_id, item_id, tipo, quantidade, valor_unitario, valor_total, motivo, defeito_fabrica, os_id, usuario_id)
  values (t.organizacao_id, p_tecnico_id, p_item_id, p_tipo, abs(p_delta), it.valor_custo, round(abs(p_delta) * it.valor_custo, 2), p_motivo, p_defeito, p_os_id, auth.uid());
  return it.valor_custo;
end;
$$;
revoke all on function public.os_mover_bolsa(uuid, uuid, numeric, public.tipo_mov_tecnico, text, boolean, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Motor: bolsa do técnico
-- -----------------------------------------------------------------------------
-- Abastecimento: transfere do estoque central para a bolsa (valor continua da empresa)
create function public.abastecer_tecnico(p_tecnico_id uuid, p_item_id uuid, p_quantidade numeric, p_observacao text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare t public.tecnicos%rowtype; it public.estoque_itens%rowtype;
begin
  select * into t from public.tecnicos where id = p_tecnico_id;
  if not found then raise exception 'Técnico não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(t.organizacao_id);
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade inválida.' using errcode = 'check_violation'; end if;
  select * into it from public.estoque_itens where id = p_item_id;
  if it.id is null or it.negocio_id <> t.negocio_id then raise exception 'Item inválido para o negócio do técnico.' using errcode = 'check_violation'; end if;
  if p_quantidade > it.quantidade_atual then
    raise exception 'Estoque central insuficiente de % (% %).', it.nome, it.quantidade_atual, it.unidade_medida using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.estoque_itens set quantidade_atual = quantidade_atual - p_quantidade where id = p_item_id;
  insert into public.estoque_movimentacoes (organizacao_id, negocio_id, item_id, tipo, origem, quantidade, valor_unitario, valor_total, data, observacao, usuario_id)
  values (it.organizacao_id, it.negocio_id, p_item_id, 'saida', 'transferencia', p_quantidade, it.valor_custo, round(p_quantidade * it.valor_custo, 2), current_date, coalesce(p_observacao, 'Bolsa: ' || t.nome), auth.uid());
  perform public.os_mover_bolsa(p_tecnico_id, p_item_id, p_quantidade, 'abastecimento', p_observacao, false, null);
end;
$$;

-- Devolução: volta da bolsa para o estoque central pelo custo médio
create function public.devolver_tecnico(p_tecnico_id uuid, p_item_id uuid, p_quantidade numeric, p_observacao text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare t public.tecnicos%rowtype; it public.estoque_itens%rowtype; saldo numeric;
begin
  select * into t from public.tecnicos where id = p_tecnico_id;
  if not found then raise exception 'Técnico não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(t.organizacao_id);
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade inválida.' using errcode = 'check_violation'; end if;
  select quantidade into saldo from public.tecnico_estoque where tecnico_id = p_tecnico_id and item_id = p_item_id;
  if coalesce(saldo, 0) < p_quantidade then raise exception 'Bolsa não tem essa quantidade (% na bolsa).', coalesce(saldo, 0) using errcode = 'check_violation'; end if;
  select * into it from public.estoque_itens where id = p_item_id;
  perform set_config('erp.motor', 'on', true);
  update public.estoque_itens set quantidade_atual = quantidade_atual + p_quantidade where id = p_item_id;
  insert into public.estoque_movimentacoes (organizacao_id, negocio_id, item_id, tipo, origem, quantidade, valor_unitario, valor_total, data, observacao, usuario_id)
  values (it.organizacao_id, it.negocio_id, p_item_id, 'entrada', 'transferencia', p_quantidade, it.valor_custo, round(p_quantidade * it.valor_custo, 2), current_date, coalesce(p_observacao, 'Devolução bolsa: ' || t.nome), auth.uid());
  perform public.os_mover_bolsa(p_tecnico_id, p_item_id, -p_quantidade, 'devolucao', p_observacao, false, null);
end;
$$;

-- Perda/avaria na bolsa: motivo obrigatório; defeito de fábrica marca sem responsabilidade.
-- Não gera cobrança do técnico (decisão do proprietário); item some da bolsa (valor já saiu do central).
create function public.perda_tecnico(p_tecnico_id uuid, p_item_id uuid, p_quantidade numeric, p_avaria boolean, p_motivo text, p_defeito_fabrica boolean default false, p_os_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare t public.tecnicos%rowtype; saldo numeric;
begin
  select * into t from public.tecnicos where id = p_tecnico_id;
  if not found then raise exception 'Técnico não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(t.organizacao_id);
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade inválida.' using errcode = 'check_violation'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Informe o motivo da perda/avaria.' using errcode = 'check_violation'; end if;
  select quantidade into saldo from public.tecnico_estoque where tecnico_id = p_tecnico_id and item_id = p_item_id;
  if coalesce(saldo, 0) < p_quantidade then raise exception 'Bolsa não tem essa quantidade (% na bolsa).', coalesce(saldo, 0) using errcode = 'check_violation'; end if;
  perform public.os_mover_bolsa(p_tecnico_id, p_item_id, -p_quantidade, case when p_avaria then 'avaria' else 'perda' end::public.tipo_mov_tecnico, p_motivo, p_defeito_fabrica, p_os_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- Motor: ciclo de vida da OS
-- -----------------------------------------------------------------------------
create function public.abrir_os(
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
declare
  n public.negocios%rowtype; ct public.contratos%rowtype; os public.ordens_servico%rowtype;
  v_tecnico uuid := p_tecnico_id; v_numero text; v_base text; v_letra int; v_retorno boolean;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(n.organizacao_id);
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
  -- atribuição automática: único técnico ativo do negócio; vários → o com menos chamados abertos
  if v_tecnico is null then
    select t.id into v_tecnico
      from public.tecnicos t
      left join public.ordens_servico o on o.tecnico_id = t.id and o.status in ('aberto', 'em_atendimento', 'pausado')
     where t.negocio_id = p_negocio_id and t.ativo
     group by t.id order by count(o.id), t.criado_em limit 1;
  elsif not exists (select 1 from public.tecnicos where id = v_tecnico and negocio_id = p_negocio_id and ativo) then
    raise exception 'Técnico inválido para este negócio.' using errcode = 'check_violation';
  end if;
  -- número: reabertura = numero original + '-' + letra; senão OS{contrato}{DDMMAAAA}{letra} ou MAN{DDMMAAAA}{letra}
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
  -- reincidência: mesmo cliente com chamado encerrado nos últimos 7 dias
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

create function public.atualizar_os(p_os_id uuid, p_tecnico_id uuid default null, p_prioridade text default null, p_cto_id uuid default null, p_observacao text default null)
returns public.ordens_servico
language plpgsql
security definer
set search_path = public
as $$
declare os public.ordens_servico%rowtype;
begin
  select * into os from public.ordens_servico where id = p_os_id;
  if not found then raise exception 'Chamado não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(os.organizacao_id);
  if os.status in ('encerrado', 'cancelado') then raise exception 'Chamado % não pode mais ser alterado.', os.numero using errcode = 'check_violation'; end if;
  if p_tecnico_id is not null and not exists (select 1 from public.tecnicos where id = p_tecnico_id and negocio_id = os.negocio_id and ativo) then
    raise exception 'Técnico inválido para este negócio.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico
     set tecnico_id = coalesce(p_tecnico_id, tecnico_id),
         prioridade = coalesce(p_prioridade::public.prioridade_os, prioridade),
         cto_id = coalesce(p_cto_id, cto_id),
         observacao = coalesce(p_observacao, observacao)
   where id = p_os_id returning * into os;
  if p_tecnico_id is not null then perform public.os_registrar_evento(p_os_id, 'atribuicao', (select nome from public.tecnicos where id = p_tecnico_id)); end if;
  return os;
end;
$$;

create function public.ciencia_os(p_os_id uuid)
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
  if os.data_ciencia is not null then return; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set data_ciencia = now() where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'ciencia');
end;
$$;

-- Agendamento inicial (obrigatório antes de iniciar). Remarcação vai por solicitar/responder.
create function public.agendar_os(p_os_id uuid, p_data date, p_hora time)
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
  if os.status not in ('aberto', 'pausado') then raise exception 'Chamado % não aceita agendamento.', os.numero using errcode = 'check_violation'; end if;
  if p_data is null or p_hora is null then raise exception 'Informe data e hora do atendimento.' using errcode = 'check_violation'; end if;
  if os.data_agendada is not null and os.status = 'aberto' and os.data_inicio is null then
    raise exception 'Chamado já agendado: peça remarcação (aval de quem abriu).' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set data_agendada = p_data, hora_agendada = p_hora where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'agendamento', to_char(p_data, 'DD/MM/YYYY') || ' ' || to_char(p_hora, 'HH24:MI'));
end;
$$;

create function public.solicitar_remarcacao_os(p_os_id uuid, p_data date, p_hora time, p_motivo text)
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
  if os.status in ('encerrado', 'cancelado') then raise exception 'Chamado finalizado.' using errcode = 'check_violation'; end if;
  if p_data is null or p_hora is null or char_length(btrim(coalesce(p_motivo, ''))) < 3 then
    raise exception 'Informe nova data, hora e o motivo.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set remarcacao_data = p_data, remarcacao_hora = p_hora, remarcacao_motivo = btrim(p_motivo) where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'remarcacao_solicitada', to_char(p_data, 'DD/MM/YYYY') || ' ' || to_char(p_hora, 'HH24:MI') || ' — ' || btrim(p_motivo));
end;
$$;

-- Aval de quem abriu (admin nesta etapa; cliente pelo portal na 29C). Não trava o chamado.
create function public.responder_remarcacao_os(p_os_id uuid, p_aprovar boolean)
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
end;
$$;

create function public.iniciar_os(p_os_id uuid)
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
  if os.status <> 'aberto' then raise exception 'Chamado % não está aberto.', os.numero using errcode = 'check_violation'; end if;
  if os.data_agendada is null then raise exception 'Agende o atendimento antes de iniciar.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set status = 'em_atendimento', data_inicio = now() where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'inicio');
end;
$$;

create function public.pausar_os(p_os_id uuid, p_motivo text)
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
  if os.status <> 'em_atendimento' then raise exception 'Só chamado em atendimento pode ser pausado.' using errcode = 'check_violation'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Informe o motivo da pausa.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set status = 'pausado', pausado_em = now() where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'pausa', btrim(p_motivo));
end;
$$;

create function public.retomar_os(p_os_id uuid)
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
  if os.status <> 'pausado' then raise exception 'Chamado não está pausado.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico
     set status = 'em_atendimento',
         tempo_pausa_minutos = tempo_pausa_minutos + greatest(0, floor(extract(epoch from (now() - pausado_em)) / 60))::int,
         pausado_em = null
   where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'retomada');
end;
$$;

-- Encerramento: consome a bolsa do técnico (pode ficar negativa — alerta), grava materiais,
-- calcula tempos e, em instalação/mudança com contrato, alimenta o payback (28B) sem tocar o central.
create function public.encerrar_os(
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
  perform public.exigir_membro(os.organizacao_id);
  if os.status not in ('em_atendimento', 'pausado') then raise exception 'Inicie o atendimento antes de encerrar.' using errcode = 'check_violation'; end if;
  if p_itens is not null and jsonb_typeof(p_itens) <> 'array' then raise exception 'Materiais devem ser uma lista.' using errcode = 'check_violation'; end if;
  if jsonb_array_length(coalesce(p_itens, '[]'::jsonb)) > 0 and os.tecnico_id is null then
    raise exception 'Chamado sem técnico não consome materiais.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  -- pausa em aberto entra na conta
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

  -- custo de aquisição do cliente (payback): instalação/mudança com contrato
  if os.tipo in ('instalacao', 'mudanca_endereco') and os.contrato_id is not null and v_material > 0 then
    insert into public.estoque_instalacoes (organizacao_id, negocio_id, pessoa_id, contrato_id, os_id, data, custo_material, mao_de_obra, tecnico, observacao, usuario_id)
    values (os.organizacao_id, os.negocio_id, os.pessoa_id, os.contrato_id, os.id, current_date, v_material, 0,
            (select nome from public.tecnicos where id = os.tecnico_id), 'Chamado ' || os.numero, auth.uid())
    returning * into v_ins;
  end if;
  perform public.os_registrar_evento(p_os_id, 'encerramento', 'Material ' || to_char(v_material, 'FM999999990.00'));
  return os;
end;
$$;

create function public.cancelar_os(p_os_id uuid, p_motivo text)
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
  if os.status in ('encerrado', 'cancelado') then raise exception 'Chamado já finalizado.' using errcode = 'check_violation'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Informe o motivo do cancelamento.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set status = 'cancelado', pausado_em = null where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'cancelamento', btrim(p_motivo));
end;
$$;

-- Avaliação (opcional). Não resolvido + reabrir → abrir_os com os_origem_id.
create function public.avaliar_os(p_os_id uuid, p_resolvido boolean, p_nota int default null)
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
  if os.status <> 'encerrado' then raise exception 'Só chamado encerrado é avaliado.' using errcode = 'check_violation'; end if;
  if p_resolvido and (p_nota is null or p_nota not between 1 and 5) then raise exception 'Nota de 1 a 5.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set avaliacao_resolvido = p_resolvido, avaliacao_nota = case when p_resolvido then p_nota end where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'avaliacao', case when p_resolvido then 'Resolvido, nota ' || p_nota else 'Não resolvido' end);
end;
$$;

-- Comissão (instalação/mudança): decisão do admin, valor editável (padrão 50% da mensalidade),
-- despesa prevista na categoria Comissões, fornecedor = pessoa do técnico, vinculada ao contrato.
create function public.aprovar_comissao_os(p_os_id uuid, p_conta_id uuid, p_vencimento date, p_valor numeric default null)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  os public.ordens_servico%rowtype; t public.tecnicos%rowtype; ct public.contratos%rowtype;
  v_valor numeric; v_cat uuid; l public.lancamentos%rowtype;
begin
  select * into os from public.ordens_servico where id = p_os_id;
  if not found then raise exception 'Chamado não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(os.organizacao_id);
  if os.status <> 'encerrado' then raise exception 'Comissão só para chamado encerrado.' using errcode = 'check_violation'; end if;
  if os.tipo not in ('instalacao', 'mudanca_endereco') then raise exception 'Comissão só para instalação ou mudança de endereço.' using errcode = 'check_violation'; end if;
  if os.comissao_lancamento_id is not null then raise exception 'Comissão já gerada para este chamado.' using errcode = 'check_violation'; end if;
  select * into t from public.tecnicos where id = os.tecnico_id;
  if t.id is null then raise exception 'Chamado sem técnico.' using errcode = 'check_violation'; end if;
  if os.contrato_id is not null then select * into ct from public.contratos where id = os.contrato_id; end if;
  v_valor := coalesce(p_valor, case when ct.id is not null then round(
    case ct.periodicidade when 'mensal' then ct.valor when 'bimestral' then ct.valor / 2 when 'trimestral' then ct.valor / 3
                          when 'semestral' then ct.valor / 6 when 'anual' then ct.valor / 12 else 0 end / 2, 2) end);
  if v_valor is null or v_valor <= 0 then raise exception 'Informe o valor da comissão (chamado sem mensalidade de referência).' using errcode = 'check_violation'; end if;
  select id into v_cat from public.categorias where organizacao_id = os.organizacao_id and tipo = 'despesa' and lower(nome) = 'comissões' limit 1;
  if v_cat is null then
    insert into public.categorias (organizacao_id, nome, tipo) values (os.organizacao_id, 'Comissões', 'despesa') returning id into v_cat;
  end if;
  l := public.criar_lancamento('despesa', 'Comissão ' || os.numero || ' — ' || t.nome, v_valor, p_vencimento, p_vencimento, null,
                               p_conta_id, null, v_cat, 'Comissão de ' || case when os.tipo = 'instalacao' then 'instalação' else 'mudança de endereço' end || ' · chamado ' || os.numero,
                               os.negocio_id, t.pessoa_id, null, false, null, null, null);
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set comissao_lancamento_id = l.id where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'comissao', to_char(v_valor, 'FM999999990.00') || ' para ' || t.nome);
  return l;
end;
$$;

revoke all on function
  public.abastecer_tecnico(uuid, uuid, numeric, text), public.devolver_tecnico(uuid, uuid, numeric, text),
  public.perda_tecnico(uuid, uuid, numeric, boolean, text, boolean, uuid),
  public.abrir_os(uuid, text, text, uuid, uuid, uuid, uuid, text, text, uuid),
  public.atualizar_os(uuid, uuid, text, uuid, text), public.ciencia_os(uuid), public.agendar_os(uuid, date, time),
  public.solicitar_remarcacao_os(uuid, date, time, text), public.responder_remarcacao_os(uuid, boolean),
  public.iniciar_os(uuid), public.pausar_os(uuid, text), public.retomar_os(uuid),
  public.encerrar_os(uuid, jsonb, text, numeric, text), public.cancelar_os(uuid, text),
  public.avaliar_os(uuid, boolean, int), public.aprovar_comissao_os(uuid, uuid, date, numeric)
from public, anon;
grant execute on function
  public.abastecer_tecnico(uuid, uuid, numeric, text), public.devolver_tecnico(uuid, uuid, numeric, text),
  public.perda_tecnico(uuid, uuid, numeric, boolean, text, boolean, uuid),
  public.abrir_os(uuid, text, text, uuid, uuid, uuid, uuid, text, text, uuid),
  public.atualizar_os(uuid, uuid, text, uuid, text), public.ciencia_os(uuid), public.agendar_os(uuid, date, time),
  public.solicitar_remarcacao_os(uuid, date, time, text), public.responder_remarcacao_os(uuid, boolean),
  public.iniciar_os(uuid), public.pausar_os(uuid, text), public.retomar_os(uuid),
  public.encerrar_os(uuid, jsonb, text, numeric, text), public.cancelar_os(uuid, text),
  public.avaliar_os(uuid, boolean, int), public.aprovar_comissao_os(uuid, uuid, date, numeric)
to authenticated;

-- -----------------------------------------------------------------------------
-- Views
-- -----------------------------------------------------------------------------
-- Payback (28B) passa a somar a comissão do chamado ao custo de aquisição do contrato.
create or replace view public.vw_payback_contrato
with (security_invoker = true) as
with custo as (
  select contrato_id, sum(custo_total) as custo, count(*) as instalacoes, min(data) as primeira_instalacao
    from public.estoque_instalacoes where contrato_id is not null group by contrato_id
), com as (
  select o.contrato_id, sum(l.valor) as comissao
    from public.ordens_servico o
    join public.lancamentos l on l.id = o.comissao_lancamento_id and l.status <> 'cancelado'
   where o.contrato_id is not null group by o.contrato_id
), base as (
  select coalesce(cu.contrato_id, co.contrato_id) as contrato_id,
         coalesce(cu.custo, 0) + coalesce(co.comissao, 0) as custo_instalacao,
         coalesce(cu.instalacoes, 0) as instalacoes, cu.primeira_instalacao
    from custo cu full join com co on co.contrato_id = cu.contrato_id
), rec as (
  select l.contrato_id, l.data_efetivacao, l.valor,
         sum(l.valor) over (partition by l.contrato_id order by l.data_efetivacao, l.criado_em rows unbounded preceding) as acumulado
    from public.lancamentos l where l.tipo = 'receita' and l.status = 'efetivado' and l.contrato_id is not null
), pago as (
  select r.contrato_id, min(r.data_efetivacao) as data_payback_real
    from rec r join base c on c.contrato_id = r.contrato_id
   where c.custo_instalacao > 0 and r.acumulado >= c.custo_instalacao group by r.contrato_id
), total as (
  select contrato_id, sum(valor) as recebido from rec group by contrato_id
)
select c.id as contrato_id, c.organizacao_id, c.negocio_id, c.pessoa_id, c.status, c.valor, c.periodicidade, c.data_inicio,
       coalesce(b.custo_instalacao, 0)::numeric(12,2) as custo_instalacao,
       coalesce(b.instalacoes, 0) as instalacoes,
       b.primeira_instalacao,
       (case c.periodicidade when 'mensal' then c.valor when 'bimestral' then c.valor / 2 when 'trimestral' then c.valor / 3
                             when 'semestral' then c.valor / 6 when 'anual' then c.valor / 12 else 0 end)::numeric(12,2) as mensalidade,
       case when b.custo_instalacao > 0 and c.periodicidade <> 'unico' and c.valor > 0
            then ceil(b.custo_instalacao / (case c.periodicidade when 'mensal' then c.valor when 'bimestral' then c.valor / 2 when 'trimestral' then c.valor / 3 when 'semestral' then c.valor / 6 else c.valor / 12 end))::int
            else null end as payback_estimado_meses,
       coalesce(t.recebido, 0)::numeric(12,2) as recebido,
       p.data_payback_real,
       case when b.custo_instalacao > 0 and p.data_payback_real is not null
            then (extract(year from age(p.data_payback_real, coalesce(b.primeira_instalacao, c.data_inicio))) * 12
                + extract(month from age(p.data_payback_real, coalesce(b.primeira_instalacao, c.data_inicio))))::int
            else null end as payback_real_meses
  from public.contratos c
  left join base b on b.contrato_id = c.id
  left join total t on t.contrato_id = c.id
  left join pago p on p.contrato_id = c.id;

-- Custo de manutenção por contrato (fora do payback): materiais de OS que não viraram instalação.
create view public.vw_os_custo_contrato
with (security_invoker = true) as
select o.organizacao_id, o.contrato_id,
       count(distinct o.id) as chamados,
       sum(m.valor_total)::numeric(12,2) as custo_material
  from public.ordens_servico o
  join public.os_materiais m on m.os_id = o.id
 where o.contrato_id is not null and o.tipo not in ('instalacao', 'mudanca_endereco')
 group by o.organizacao_id, o.contrato_id;

-- Bolsa consolidada por técnico (para alertas e valor em campo)
create view public.vw_bolsa_tecnicos
with (security_invoker = true) as
select te.organizacao_id, te.tecnico_id, t.negocio_id, t.nome as tecnico, t.ativo,
       count(*) filter (where te.quantidade < 0) as itens_negativos,
       count(*) filter (where te.quantidade >= 0 and te.quantidade < te.quantidade_minima) as itens_abaixo_minimo,
       sum(te.quantidade * i.valor_custo)::numeric(12,2) as valor_em_campo
  from public.tecnico_estoque te
  join public.tecnicos t on t.id = te.tecnico_id
  join public.estoque_itens i on i.id = te.item_id
 group by te.organizacao_id, te.tecnico_id, t.negocio_id, t.nome, t.ativo;

-- -----------------------------------------------------------------------------
-- RLS e permissões
-- -----------------------------------------------------------------------------
alter table public.tecnicos enable row level security;
alter table public.tecnico_estoque enable row level security;
alter table public.tecnico_movimentacoes enable row level security;
alter table public.ordens_servico enable row level security;
alter table public.os_materiais enable row level security;
alter table public.os_historico enable row level security;
create policy tecnicos_org on public.tecnicos using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy tecnico_estoque_org on public.tecnico_estoque using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy tecnico_mov_org on public.tecnico_movimentacoes using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy os_org on public.ordens_servico using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy os_materiais_org on public.os_materiais using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy os_historico_org on public.os_historico using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.tecnicos, public.tecnico_estoque, public.tecnico_movimentacoes, public.ordens_servico, public.os_materiais, public.os_historico from public, anon, authenticated;
grant select, insert, update on public.tecnicos to authenticated;
grant select, insert, update on public.tecnico_estoque to authenticated; -- quantidade protegida por trigger; mínimo é configurável
grant select, insert on public.tecnico_movimentacoes, public.os_historico, public.os_materiais to authenticated;
grant select, insert, update on public.ordens_servico to authenticated;
revoke all on public.vw_os_custo_contrato, public.vw_bolsa_tecnicos from public, anon;
grant select on public.vw_os_custo_contrato, public.vw_bolsa_tecnicos to authenticated;
