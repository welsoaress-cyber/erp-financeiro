-- =============================================================================
-- 0058 · Etapa 30 — Comodato: equipamentos na casa do cliente (ONU, roteador)
-- =============================================================================
-- Cada equipamento entregue ao cliente vira um registro de COMODATO com número
-- de série, vinculado a pessoa/contrato e à OS. Decisões do proprietário:
-- - Instalação: no encerramento da OS o técnico informa a série; o equipamento
--   sai da bolsa dele (consumo, custo médio) e entra no custo do chamado.
-- - Uma série só pode estar instalada em um cliente por vez (por organização).
-- - Contrato encerrado com equipamento instalado gera automaticamente uma OS
--   de RECOLHIMENTO (novo tipo) para o técnico buscar o equipamento.
-- - Recolhimento: volta ao estoque central pelo custo médio (ou descarte, se
--   danificado — fica só o histórico). Troca: o antigo vira 'trocado' (com
--   defeito de fábrica ou não) e o novo sai da bolsa do técnico. Perda exige
--   justificativa. Tudo imutável no histórico e auditado.
-- - Registro manual (equipamento que já estava no cliente antes do sistema)
--   não mexe no estoque.
-- =============================================================================

alter type public.tipo_os add value if not exists 'recolhimento';
create type public.status_comodato as enum ('instalado', 'recolhido', 'trocado', 'perdido');
create type public.evento_comodato as enum ('instalacao', 'registro', 'recolhimento', 'descarte', 'troca', 'perda');

create table public.comodatos (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  item_id uuid not null references public.estoque_itens (id),
  numero_serie text not null check (char_length(btrim(numero_serie)) between 3 and 40),
  pessoa_id uuid not null references public.pessoas (id),
  contrato_id uuid references public.contratos (id),
  tecnico_id uuid references public.tecnicos (id),
  status public.status_comodato not null default 'instalado',
  data_instalacao date not null default current_date,
  data_recolhimento date,
  os_instalacao_id uuid references public.ordens_servico (id),
  os_recolhimento_id uuid references public.ordens_servico (id),
  observacao text check (observacao is null or char_length(observacao) <= 300),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create unique index comodatos_serie_instalada on public.comodatos (organizacao_id, upper(btrim(numero_serie))) where status = 'instalado';
create index comodatos_pessoa on public.comodatos (pessoa_id);
create index comodatos_contrato on public.comodatos (contrato_id) where contrato_id is not null;
create trigger comodatos_atualizado before update on public.comodatos for each row execute function public.tg_atualizado_em();
create trigger comodatos_auditoria after insert or update or delete on public.comodatos for each row execute function public.tg_auditoria();

create table public.comodato_historico (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  comodato_id uuid not null references public.comodatos (id),
  evento public.evento_comodato not null,
  os_id uuid references public.ordens_servico (id),
  observacao text check (observacao is null or char_length(observacao) <= 300),
  usuario_id uuid,
  criado_em timestamptz not null default now()
);
create index comodato_historico_comodato on public.comodato_historico (comodato_id, criado_em);

-- escrita só pelo motor; histórico imutável
create or replace function public.tg_comodato_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'comodato_historico' and tg_op in ('UPDATE', 'DELETE') then
    raise exception 'Histórico de comodato é imutável.' using errcode = 'check_violation';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Comodato não é excluído: recolha, troque ou registre a perda.' using errcode = 'check_violation';
  end if;
  if coalesce(current_setting('erp.motor', true), '') <> 'on' then
    raise exception 'Comodato é gravado pelo motor (instalar/registrar/recolher/trocar).' using errcode = 'insufficient_privilege';
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function public.tg_comodato_protecao() from public, anon, authenticated;
create trigger comodatos_protecao before insert or update or delete on public.comodatos for each row execute function public.tg_comodato_protecao();
create trigger comodato_historico_protecao before insert or update or delete on public.comodato_historico for each row execute function public.tg_comodato_protecao();

-- -----------------------------------------------------------------------------
-- Auxiliar interno: cria comodato + histórico (sem checar permissão)
-- -----------------------------------------------------------------------------
create function public.comodato_criar_interno(
  p_negocio_id uuid, p_item_id uuid, p_serie text, p_pessoa_id uuid, p_contrato_id uuid,
  p_tecnico_id uuid, p_os_id uuid, p_evento public.evento_comodato, p_observacao text
)
returns public.comodatos
language plpgsql
security definer
set search_path = public
as $$
declare it public.estoque_itens%rowtype; c public.comodatos%rowtype;
begin
  select * into it from public.estoque_itens where id = p_item_id;
  if it.id is null or it.negocio_id <> p_negocio_id then raise exception 'Item de estoque inválido para este negócio.' using errcode = 'check_violation'; end if;
  if p_contrato_id is not null and not exists (select 1 from public.contratos where id = p_contrato_id and pessoa_id = p_pessoa_id) then
    raise exception 'Contrato inválido: precisa ser do cliente.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  insert into public.comodatos (organizacao_id, negocio_id, item_id, numero_serie, pessoa_id, contrato_id, tecnico_id, os_instalacao_id, observacao)
  values (it.organizacao_id, p_negocio_id, p_item_id, upper(btrim(p_serie)), p_pessoa_id, p_contrato_id, p_tecnico_id, p_os_id, p_observacao)
  returning * into c;
  insert into public.comodato_historico (organizacao_id, comodato_id, evento, os_id, observacao, usuario_id)
  values (c.organizacao_id, c.id, p_evento, p_os_id, p_observacao, auth.uid());
  return c;
exception when unique_violation then
  raise exception 'A série % já está instalada em um cliente.', upper(btrim(p_serie)) using errcode = 'check_violation';
end;
$$;
revoke all on function public.comodato_criar_interno(uuid, uuid, text, uuid, uuid, uuid, uuid, public.evento_comodato, text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Encerramento da OS ganha os equipamentos instalados (série sai da bolsa)
-- p_equipamentos: [{"item_id": uuid, "numero_serie": text}, ...]
-- -----------------------------------------------------------------------------
drop function public.encerrar_os(uuid, jsonb, text, numeric, text);
create function public.encerrar_os(
  p_os_id uuid, p_itens jsonb default '[]'::jsonb, p_diagnostico text default null,
  p_sinal_dbm numeric default null, p_observacao text default null, p_equipamentos jsonb default '[]'::jsonb
)
returns public.ordens_servico
language plpgsql
security definer
set search_path = public
as $$
declare
  os public.ordens_servico%rowtype; linha jsonb; v_item uuid; v_qtd numeric; v_custo numeric; v_material numeric := 0;
  v_agendado timestamptz; v_pausa int; v_ins public.estoque_instalacoes%rowtype; v_serie text;
begin
  select * into os from public.ordens_servico where id = p_os_id;
  if not found then raise exception 'Chamado não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro_ou_tecnico_os(os);
  if os.status not in ('em_atendimento', 'pausado') then raise exception 'Inicie o atendimento antes de encerrar.' using errcode = 'check_violation'; end if;
  if p_itens is not null and jsonb_typeof(p_itens) <> 'array' then raise exception 'Materiais devem ser uma lista.' using errcode = 'check_violation'; end if;
  if p_equipamentos is not null and jsonb_typeof(p_equipamentos) <> 'array' then raise exception 'Equipamentos devem ser uma lista.' using errcode = 'check_violation'; end if;
  if (jsonb_array_length(coalesce(p_itens, '[]'::jsonb)) > 0 or jsonb_array_length(coalesce(p_equipamentos, '[]'::jsonb)) > 0) and os.tecnico_id is null then
    raise exception 'Chamado sem técnico não consome materiais.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(coalesce(p_equipamentos, '[]'::jsonb)) > 0 and os.pessoa_id is null then
    raise exception 'Equipamento em comodato exige cliente no chamado.' using errcode = 'check_violation';
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

  -- equipamentos: 1 unidade da bolsa por série + registro de comodato
  for linha in select * from jsonb_array_elements(coalesce(p_equipamentos, '[]'::jsonb)) loop
    v_item := (linha->>'item_id')::uuid;
    v_serie := linha->>'numero_serie';
    if char_length(btrim(coalesce(v_serie, ''))) < 3 then raise exception 'Informe o número de série do equipamento.' using errcode = 'check_violation'; end if;
    v_custo := public.os_mover_bolsa(os.tecnico_id, v_item, -1, 'consumo', 'Comodato ' || upper(btrim(v_serie)), false, os.id);
    insert into public.os_materiais (organizacao_id, os_id, item_id, quantidade, valor_unitario, valor_total)
    values (os.organizacao_id, os.id, v_item, 1, v_custo, round(v_custo, 2));
    v_material := v_material + round(v_custo, 2);
    perform public.comodato_criar_interno(os.negocio_id, v_item, v_serie, os.pessoa_id, os.contrato_id, os.tecnico_id, os.id, 'instalacao', p_observacao);
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

  -- OS de recolhimento encerrada: recolhe automaticamente os comodatos pendentes dela
  if os.tipo::text = 'recolhimento' then
    update public.comodatos set status = 'recolhido', data_recolhimento = current_date, os_recolhimento_id = os.id
     where pessoa_id = os.pessoa_id and status = 'instalado' and (os.contrato_id is null or contrato_id = os.contrato_id);
    insert into public.comodato_historico (organizacao_id, comodato_id, evento, os_id, observacao, usuario_id)
    select organizacao_id, id, 'recolhimento', os.id, 'Recolhido no chamado ' || os.numero, auth.uid()
      from public.comodatos where os_recolhimento_id = os.id;
    -- devolve ao estoque central pelo custo médio
    perform public.entrada_estoque(c.item_id, 1, i.valor_custo, current_date, 'devolucao', null, 'Comodato recolhido: ' || c.numero_serie)
      from public.comodatos c join public.estoque_itens i on i.id = c.item_id where c.os_recolhimento_id = os.id;
  end if;

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
revoke all on function public.encerrar_os(uuid, jsonb, text, numeric, text, jsonb) from public, anon;
grant execute on function public.encerrar_os(uuid, jsonb, text, numeric, text, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- Motor: ações do admin sobre o comodato
-- -----------------------------------------------------------------------------
-- Registro manual (equipamento que já estava no cliente): não mexe no estoque
create function public.registrar_comodato(p_negocio_id uuid, p_item_id uuid, p_serie text, p_pessoa_id uuid, p_contrato_id uuid default null, p_observacao text default null)
returns public.comodatos
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(n.organizacao_id);
  if not exists (select 1 from public.pessoas where id = p_pessoa_id and organizacao_id = n.organizacao_id) then
    raise exception 'Cliente inválido.' using errcode = 'check_violation';
  end if;
  return public.comodato_criar_interno(p_negocio_id, p_item_id, p_serie, p_pessoa_id, p_contrato_id, null, null, 'registro', coalesce(p_observacao, 'Registro manual (sem baixa de estoque)'));
end;
$$;

-- Recolhimento direto pelo admin (sem OS): volta ao central ou descarta
create function public.recolher_comodato(p_comodato_id uuid, p_descartar boolean default false, p_observacao text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare c public.comodatos%rowtype; it public.estoque_itens%rowtype;
begin
  select * into c from public.comodatos where id = p_comodato_id;
  if not found then raise exception 'Comodato não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(c.organizacao_id);
  if c.status <> 'instalado' then raise exception 'Equipamento não está instalado.' using errcode = 'check_violation'; end if;
  if p_descartar and char_length(btrim(coalesce(p_observacao, ''))) < 3 then
    raise exception 'Informe o motivo do descarte.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.comodatos set status = 'recolhido', data_recolhimento = current_date, observacao = coalesce(p_observacao, observacao) where id = p_comodato_id;
  insert into public.comodato_historico (organizacao_id, comodato_id, evento, observacao, usuario_id)
  values (c.organizacao_id, c.id, case when p_descartar then 'descarte' else 'recolhimento' end::public.evento_comodato, p_observacao, auth.uid());
  if not p_descartar then
    select * into it from public.estoque_itens where id = c.item_id;
    perform public.entrada_estoque(c.item_id, 1, it.valor_custo, current_date, 'devolucao', null, 'Comodato recolhido: ' || c.numero_serie);
  end if;
end;
$$;

-- Troca: antigo sai (defeito de fábrica não volta; senão volta ao central), novo sai da bolsa do técnico
create function public.trocar_comodato(p_comodato_id uuid, p_serie_nova text, p_tecnico_id uuid, p_defeito_fabrica boolean, p_motivo text, p_os_id uuid default null)
returns public.comodatos
language plpgsql
security definer
set search_path = public
as $$
declare c public.comodatos%rowtype; it public.estoque_itens%rowtype; novo public.comodatos%rowtype;
begin
  select * into c from public.comodatos where id = p_comodato_id;
  if not found then raise exception 'Comodato não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(c.organizacao_id);
  if c.status <> 'instalado' then raise exception 'Equipamento não está instalado.' using errcode = 'check_violation'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Informe o motivo da troca.' using errcode = 'check_violation'; end if;
  if not exists (select 1 from public.tecnicos where id = p_tecnico_id and negocio_id = c.negocio_id and ativo) then
    raise exception 'Técnico inválido.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.comodatos set status = 'trocado', data_recolhimento = current_date where id = p_comodato_id;
  insert into public.comodato_historico (organizacao_id, comodato_id, evento, os_id, observacao, usuario_id)
  values (c.organizacao_id, c.id, 'troca', p_os_id, p_motivo || case when p_defeito_fabrica then ' (defeito de fábrica)' else '' end, auth.uid());
  if not p_defeito_fabrica then
    select * into it from public.estoque_itens where id = c.item_id;
    perform public.entrada_estoque(c.item_id, 1, it.valor_custo, current_date, 'devolucao', null, 'Troca de comodato: ' || c.numero_serie);
  end if;
  -- novo equipamento sai da bolsa do técnico
  perform public.os_mover_bolsa(p_tecnico_id, c.item_id, -1, 'consumo', 'Troca comodato ' || upper(btrim(p_serie_nova)), false, p_os_id);
  novo := public.comodato_criar_interno(c.negocio_id, c.item_id, p_serie_nova, c.pessoa_id, c.contrato_id, p_tecnico_id, p_os_id, 'troca', 'Substitui ' || c.numero_serie || ': ' || p_motivo);
  return novo;
end;
$$;

-- Perda (cliente sumiu com o equipamento): justificativa obrigatória
create function public.perda_comodato(p_comodato_id uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare c public.comodatos%rowtype;
begin
  select * into c from public.comodatos where id = p_comodato_id;
  if not found then raise exception 'Comodato não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(c.organizacao_id);
  if c.status <> 'instalado' then raise exception 'Equipamento não está instalado.' using errcode = 'check_violation'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Informe a justificativa da perda.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.comodatos set status = 'perdido', data_recolhimento = current_date, observacao = p_motivo where id = p_comodato_id;
  insert into public.comodato_historico (organizacao_id, comodato_id, evento, observacao, usuario_id)
  values (c.organizacao_id, c.id, 'perda', p_motivo, auth.uid());
end;
$$;

revoke all on function public.registrar_comodato(uuid, uuid, text, uuid, uuid, text), public.recolher_comodato(uuid, boolean, text),
  public.trocar_comodato(uuid, text, uuid, boolean, text, uuid), public.perda_comodato(uuid, text) from public, anon;
grant execute on function public.registrar_comodato(uuid, uuid, text, uuid, uuid, text), public.recolher_comodato(uuid, boolean, text),
  public.trocar_comodato(uuid, text, uuid, boolean, text, uuid), public.perda_comodato(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Contrato encerrado com equipamento instalado → OS de recolhimento automática
-- -----------------------------------------------------------------------------
create or replace function public.tg_contrato_recolhimento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_series text;
begin
  if new.status = 'encerrado' and old.status <> 'encerrado' then
    select string_agg(numero_serie, ', ') into v_series
      from public.comodatos where contrato_id = new.id and status = 'instalado';
    if v_series is not null and not exists (
      select 1 from public.ordens_servico
       where contrato_id = new.id and tipo::text = 'recolhimento' and status in ('aberto', 'em_atendimento', 'pausado')) then
      perform public.os_abrir_interna(new.negocio_id, 'recolhimento',
        'Recolher equipamento(s) em comodato: ' || v_series || ' (contrato encerrado)',
        new.pessoa_id, new.id, null, null, 'normal', 'interno', null);
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.tg_contrato_recolhimento() from public, anon, authenticated;
create trigger contratos_recolhimento after update on public.contratos for each row execute function public.tg_contrato_recolhimento();

-- -----------------------------------------------------------------------------
-- RLS e permissões
-- -----------------------------------------------------------------------------
alter table public.comodatos enable row level security;
alter table public.comodato_historico enable row level security;
create policy comodatos_org on public.comodatos for select using (organizacao_id in (select public.minhas_organizacoes()));
create policy comodato_historico_org on public.comodato_historico for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.comodatos, public.comodato_historico from public, anon, authenticated;
grant select on public.comodatos, public.comodato_historico to authenticated;
