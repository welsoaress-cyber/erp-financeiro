-- =============================================================================
-- 0091 · Comodato: entregar baixa do estoque, recolher só devolve o que saiu
-- =============================================================================
-- Assimetria encontrada em produção: "Registrar comodato" NÃO baixava o estoque
-- (era feito para cadastrar equipamento que já estava na casa do cliente antes
-- do ERP), mas TODO recolhimento dava entrada. Registrar e recolher algumas
-- vezes inflava o saldo sozinho, do nada.
--
-- Agora cada comodato guarda se saiu ou não do estoque (baixou_estoque):
--   • registrar_comodato ganha p_baixar_estoque (padrão true) e dá a saída;
--     desmarcar é para equipamento legado, que nunca esteve no seu estoque.
--   • recolher, trocar e o recolhimento pela OS só devolvem ao estoque o que
--     de fato saiu dele.
-- Comodato criado pela OS continua como sempre: o item já saiu do central quando
-- foi para a bolsa do técnico, então baixou_estoque = true.
-- =============================================================================

alter table public.comodatos
  add column if not exists baixou_estoque boolean not null default true;

comment on column public.comodatos.baixou_estoque is
  'Falso só para equipamento legado, registrado sem nunca ter passado pelo estoque: recolher não devolve ao saldo.';

-- backfill: os registros manuais antigos nasceram sem baixa de estoque
update public.comodatos c set baixou_estoque = false
 where exists (select 1 from public.comodato_historico h where h.comodato_id = c.id and h.evento = 'registro');

-- -----------------------------------------------------------------------------
-- Criação interna: recebe se houve baixa de estoque
-- -----------------------------------------------------------------------------
drop function if exists public.comodato_criar_interno(uuid, uuid, text, uuid, uuid, uuid, uuid, public.evento_comodato, text);

create function public.comodato_criar_interno(
  p_negocio_id uuid, p_item_id uuid, p_serie text, p_pessoa_id uuid, p_contrato_id uuid,
  p_tecnico_id uuid, p_os_id uuid, p_evento public.evento_comodato, p_observacao text,
  p_baixou_estoque boolean default true
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
  insert into public.comodatos (organizacao_id, negocio_id, item_id, numero_serie, pessoa_id, contrato_id, tecnico_id, os_instalacao_id, observacao, baixou_estoque)
  values (it.organizacao_id, p_negocio_id, p_item_id, upper(btrim(p_serie)), p_pessoa_id, p_contrato_id, p_tecnico_id, p_os_id, p_observacao, coalesce(p_baixou_estoque, true))
  returning * into c;
  insert into public.comodato_historico (organizacao_id, comodato_id, evento, os_id, observacao, usuario_id)
  values (c.organizacao_id, c.id, p_evento, p_os_id, p_observacao, auth.uid());
  return c;
exception when unique_violation then
  raise exception 'A série % já está instalada em um cliente.', upper(btrim(p_serie)) using errcode = 'check_violation';
end;
$$;
revoke all on function public.comodato_criar_interno(uuid, uuid, text, uuid, uuid, uuid, uuid, public.evento_comodato, text, boolean) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Registro pelo admin: por padrão TIRA do estoque (o caminho de todo dia)
-- -----------------------------------------------------------------------------
drop function if exists public.registrar_comodato(uuid, uuid, text, uuid, uuid, text);

create function public.registrar_comodato(
  p_negocio_id uuid, p_item_id uuid, p_serie text, p_pessoa_id uuid,
  p_contrato_id uuid default null, p_observacao text default null,
  p_baixar_estoque boolean default true
)
returns public.comodatos
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; v_baixa boolean := coalesce(p_baixar_estoque, true); c public.comodatos%rowtype;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(n.organizacao_id);
  if not exists (select 1 from public.pessoas where id = p_pessoa_id and organizacao_id = n.organizacao_id) then
    raise exception 'Cliente inválido.' using errcode = 'check_violation';
  end if;
  c := public.comodato_criar_interno(
    p_negocio_id, p_item_id, p_serie, p_pessoa_id, p_contrato_id, null, null, 'registro',
    coalesce(p_observacao, case when v_baixa then 'Entrega registrada pelo administrador' else 'Equipamento legado (sem baixa de estoque)' end),
    v_baixa);
  -- a saída sai depois da criação: se a série estiver duplicada, o estoque não se mexe
  if v_baixa then
    -- sem pessoa/contrato de propósito: o vínculo com o cliente é a própria tabela comodatos,
    -- e repeti-lo aqui faria o equipamento aparecer duas vezes no relatório de materiais do cliente
    perform public.saida_estoque(p_item_id, 1, 'instalacao', current_date, null, null,
      'Comodato ' || upper(btrim(p_serie)) || ' — ' || (select nome from public.pessoas where id = p_pessoa_id));
  end if;
  return c;
end;
$$;
revoke all on function public.registrar_comodato(uuid, uuid, text, uuid, uuid, text, boolean) from public, anon;
grant execute on function public.registrar_comodato(uuid, uuid, text, uuid, uuid, text, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- Recolher e trocar: só devolve ao estoque o que saiu dele
-- -----------------------------------------------------------------------------
create or replace function public.recolher_comodato(p_comodato_id uuid, p_descartar boolean default false, p_observacao text default null)
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
  if not p_descartar and c.baixou_estoque then
    select * into it from public.estoque_itens where id = c.item_id;
    perform public.entrada_estoque(c.item_id, 1, it.valor_custo, current_date, 'devolucao', null, 'Comodato recolhido: ' || c.numero_serie);
  end if;
end;
$$;

create or replace function public.trocar_comodato(p_comodato_id uuid, p_serie_nova text, p_tecnico_id uuid, p_defeito_fabrica boolean, p_motivo text, p_os_id uuid default null)
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
  if not p_defeito_fabrica and c.baixou_estoque then
    select * into it from public.estoque_itens where id = c.item_id;
    perform public.entrada_estoque(c.item_id, 1, it.valor_custo, current_date, 'devolucao', null, 'Troca de comodato: ' || c.numero_serie);
  end if;
  -- novo equipamento sai da bolsa do técnico: saiu do estoque quando abasteceu a bolsa
  perform public.os_mover_bolsa(p_tecnico_id, c.item_id, -1, 'consumo', 'Troca comodato ' || upper(btrim(p_serie_nova)), false, p_os_id);
  novo := public.comodato_criar_interno(c.negocio_id, c.item_id, p_serie_nova, c.pessoa_id, c.contrato_id, p_tecnico_id, p_os_id, 'troca', 'Substitui ' || c.numero_serie || ': ' || p_motivo, true);
  return novo;
end;
$$;

-- -----------------------------------------------------------------------------
-- encerrar_os: cópia da 0058, só o recolhimento passa a respeitar baixou_estoque
-- -----------------------------------------------------------------------------
create or replace function public.encerrar_os(
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
      from public.comodatos c join public.estoque_itens i on i.id = c.item_id
     where c.os_recolhimento_id = os.id and c.baixou_estoque;
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