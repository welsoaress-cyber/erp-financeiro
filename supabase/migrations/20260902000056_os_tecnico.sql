-- =============================================================================
-- 0056 · Etapa 29B — Login e acesso restrito do TÉCNICO
-- =============================================================================
-- O técnico entra no mesmo app com usuário/senha (sem e-mail: o app converte o
-- login para login@tecnico.local no Supabase Auth). Ele NÃO é membro da
-- organização: minhas_organizacoes() devolve vazio e, portanto, ele não enxerga
-- NADA do ERP por padrão. Este arquivo abre só o mínimo:
-- - ver o próprio cadastro, a própria bolsa/movimentações e os próprios chamados
--   (com materiais e histórico) — nunca os tempos serem exibidos é papel do app;
-- - agir nos próprios chamados: ciência, agendar, remarcação, iniciar, pausar,
--   retomar, encerrar; registrar perda da própria bolsa; pedir reposição; foto.
-- - dados mínimos do cliente do chamado via RPC (nome, telefone, endereço,
--   contrato e CTO) — sem acesso à tabela pessoas.
-- Abrir/cancelar/avaliar/comissionar/abastecer continuam só do admin (membro).
-- Fotos: bucket os-fotos (Storage), até 3 por chamado, referenciadas em os_fotos.
-- =============================================================================

alter table public.tecnicos add column login text check (login is null or login ~ '^[a-z0-9._-]{3,30}$');
create unique index tecnicos_login_unico on public.tecnicos (organizacao_id, login) where login is not null;
create unique index tecnicos_usuario_unico on public.tecnicos (usuario_id) where usuario_id is not null;

-- usuário criado com metadata tecnico=true não ganha organização própria
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
  if coalesce(new.raw_user_meta_data ->> 'tecnico', '') = 'true' then
    return new;  -- técnico: o admin grava tecnicos.usuario_id ao criar o login
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

-- -----------------------------------------------------------------------------
-- Helpers de permissão
-- -----------------------------------------------------------------------------
create function public.tecnico_do_usuario()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.tecnicos where usuario_id = auth.uid() and ativo;
$$;

create function public.minhas_os()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.ordens_servico where tecnico_id in (select public.tecnico_do_usuario());
$$;

-- membro da organização OU técnico responsável pelo chamado
create function public.exigir_membro_ou_tecnico_os(p_os public.ordens_servico)
returns void
language plpgsql
stable
set search_path = public
as $$
begin
  if p_os.organizacao_id in (select public.minhas_organizacoes()) then return; end if;
  if p_os.tecnico_id is not null and p_os.tecnico_id in (select public.tecnico_do_usuario()) then return; end if;
  raise exception 'Sem permissão para este chamado.' using errcode = 'insufficient_privilege';
end;
$$;

create function public.exigir_membro_ou_dono_tecnico(p_tecnico_id uuid)
returns void
language plpgsql
stable
set search_path = public
as $$
declare v_org uuid;
begin
  select organizacao_id into v_org from public.tecnicos where id = p_tecnico_id;
  if v_org is null then raise exception 'Técnico não encontrado.' using errcode = 'no_data_found'; end if;
  if v_org in (select public.minhas_organizacoes()) then return; end if;
  if p_tecnico_id in (select public.tecnico_do_usuario()) then return; end if;
  raise exception 'Sem permissão para este técnico.' using errcode = 'insufficient_privilege';
end;
$$;

revoke all on function public.tecnico_do_usuario(), public.minhas_os(),
  public.exigir_membro_ou_tecnico_os(public.ordens_servico), public.exigir_membro_ou_dono_tecnico(uuid)
from public, anon;
grant execute on function public.tecnico_do_usuario(), public.minhas_os(),
  public.exigir_membro_ou_tecnico_os(public.ordens_servico), public.exigir_membro_ou_dono_tecnico(uuid)
to authenticated;

-- -----------------------------------------------------------------------------
-- Leitura do técnico (políticas permissivas somam-se às de organização)
-- -----------------------------------------------------------------------------
create policy tecnicos_self on public.tecnicos for select using (usuario_id = auth.uid());
create policy os_do_tecnico on public.ordens_servico for select using (tecnico_id in (select public.tecnico_do_usuario()));
create policy os_materiais_tecnico on public.os_materiais for select using (os_id in (select public.minhas_os()));
create policy os_historico_tecnico on public.os_historico for select using (os_id in (select public.minhas_os()));
create policy tecnico_estoque_self on public.tecnico_estoque for select using (tecnico_id in (select public.tecnico_do_usuario()));
create policy tecnico_mov_self on public.tecnico_movimentacoes for select using (tecnico_id in (select public.tecnico_do_usuario()));
create policy estoque_itens_tecnico on public.estoque_itens for select
  using (negocio_id in (select negocio_id from public.tecnicos where usuario_id = auth.uid() and ativo));

-- -----------------------------------------------------------------------------
-- Ações do técnico nos próprios chamados: troca exigir_membro pela checagem dupla
-- (corpos idênticos aos da 0055 fora a linha de permissão)
-- -----------------------------------------------------------------------------
create or replace function public.ciencia_os(p_os_id uuid)
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
  if os.data_ciencia is not null then return; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set data_ciencia = now() where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'ciencia');
end;
$$;

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
end;
$$;

create or replace function public.solicitar_remarcacao_os(p_os_id uuid, p_data date, p_hora time, p_motivo text)
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
  if os.status in ('encerrado', 'cancelado') then raise exception 'Chamado finalizado.' using errcode = 'check_violation'; end if;
  if p_data is null or p_hora is null or char_length(btrim(coalesce(p_motivo, ''))) < 3 then
    raise exception 'Informe nova data, hora e o motivo.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set remarcacao_data = p_data, remarcacao_hora = p_hora, remarcacao_motivo = btrim(p_motivo) where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'remarcacao_solicitada', to_char(p_data, 'DD/MM/YYYY') || ' ' || to_char(p_hora, 'HH24:MI') || ' — ' || btrim(p_motivo));
end;
$$;

create or replace function public.iniciar_os(p_os_id uuid)
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
  if os.status <> 'aberto' then raise exception 'Chamado % não está aberto.', os.numero using errcode = 'check_violation'; end if;
  if os.data_agendada is null then raise exception 'Agende o atendimento antes de iniciar.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set status = 'em_atendimento', data_inicio = now() where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'inicio');
end;
$$;

create or replace function public.pausar_os(p_os_id uuid, p_motivo text)
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
  if os.status <> 'em_atendimento' then raise exception 'Só chamado em atendimento pode ser pausado.' using errcode = 'check_violation'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Informe o motivo da pausa.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.ordens_servico set status = 'pausado', pausado_em = now() where id = p_os_id;
  perform public.os_registrar_evento(p_os_id, 'pausa', btrim(p_motivo));
end;
$$;

create or replace function public.retomar_os(p_os_id uuid)
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
  return os;
end;
$$;

create or replace function public.perda_tecnico(p_tecnico_id uuid, p_item_id uuid, p_quantidade numeric, p_avaria boolean, p_motivo text, p_defeito_fabrica boolean default false, p_os_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare saldo numeric;
begin
  perform public.exigir_membro_ou_dono_tecnico(p_tecnico_id);
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade inválida.' using errcode = 'check_violation'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Informe o motivo da perda/avaria.' using errcode = 'check_violation'; end if;
  select quantidade into saldo from public.tecnico_estoque where tecnico_id = p_tecnico_id and item_id = p_item_id;
  if coalesce(saldo, 0) < p_quantidade then raise exception 'Bolsa não tem essa quantidade (% na bolsa).', coalesce(saldo, 0) using errcode = 'check_violation'; end if;
  perform public.os_mover_bolsa(p_tecnico_id, p_item_id, -p_quantidade, case when p_avaria then 'avaria' else 'perda' end::public.tipo_mov_tecnico, p_motivo, p_defeito_fabrica, p_os_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- Dados mínimos do cliente do chamado (sem abrir a tabela pessoas ao técnico)
-- -----------------------------------------------------------------------------
create function public.os_info_cliente(p_os_id uuid)
returns table (cliente text, telefone text, endereco text, contrato text, cto text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare os public.ordens_servico%rowtype;
begin
  select * into os from public.ordens_servico where id = p_os_id;
  if not found then raise exception 'Chamado não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro_ou_tecnico_os(os);
  return query
  select p.nome, p.telefone, p.endereco,
         case when c.id is not null then '#' || lpad(c.codigo::text, 3, '0') end,
         ct.codigo
    from public.ordens_servico o
    left join public.pessoas p on p.id = o.pessoa_id
    left join public.contratos c on c.id = o.contrato_id
    left join public.ctos ct on ct.id = o.cto_id
   where o.id = p_os_id;
end;
$$;
revoke all on function public.os_info_cliente(uuid) from public, anon;
grant execute on function public.os_info_cliente(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Pedido de reposição da bolsa
-- -----------------------------------------------------------------------------
create table public.reposicao_solicitacoes (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  tecnico_id uuid not null references public.tecnicos (id),
  item_id uuid not null references public.estoque_itens (id),
  quantidade numeric(12,2) not null check (quantidade > 0),
  atendida boolean not null default false,
  criado_em timestamptz not null default now(),
  atendida_em timestamptz
);
create index reposicao_pendentes on public.reposicao_solicitacoes (organizacao_id) where not atendida;
alter table public.reposicao_solicitacoes enable row level security;
create policy reposicao_org on public.reposicao_solicitacoes using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy reposicao_tecnico on public.reposicao_solicitacoes for select using (tecnico_id in (select public.tecnico_do_usuario()));
revoke all on public.reposicao_solicitacoes from public, anon, authenticated;
grant select on public.reposicao_solicitacoes to authenticated;

create function public.solicitar_reposicao(p_item_id uuid, p_quantidade numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_tec uuid; t public.tecnicos%rowtype; it public.estoque_itens%rowtype;
begin
  select id into v_tec from public.tecnicos where usuario_id = auth.uid() and ativo;
  if v_tec is null then raise exception 'Apenas o técnico pede reposição da própria bolsa.' using errcode = 'insufficient_privilege'; end if;
  select * into t from public.tecnicos where id = v_tec;
  select * into it from public.estoque_itens where id = p_item_id;
  if it.id is null or it.negocio_id <> t.negocio_id then raise exception 'Item inválido.' using errcode = 'check_violation'; end if;
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade inválida.' using errcode = 'check_violation'; end if;
  insert into public.reposicao_solicitacoes (organizacao_id, tecnico_id, item_id, quantidade) values (t.organizacao_id, v_tec, p_item_id, p_quantidade);
end;
$$;
revoke all on function public.solicitar_reposicao(uuid, numeric) from public, anon;
grant execute on function public.solicitar_reposicao(uuid, numeric) to authenticated;

-- abastecer passa a marcar as solicitações pendentes daquele item como atendidas
create or replace function public.abastecer_tecnico(p_tecnico_id uuid, p_item_id uuid, p_quantidade numeric, p_observacao text default null)
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
  update public.reposicao_solicitacoes set atendida = true, atendida_em = now()
   where tecnico_id = p_tecnico_id and item_id = p_item_id and not atendida;
end;
$$;

-- -----------------------------------------------------------------------------
-- Fotos do chamado (Storage: bucket os-fotos; até 3 por chamado)
-- -----------------------------------------------------------------------------
create table public.os_fotos (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  os_id uuid not null references public.ordens_servico (id),
  caminho text not null unique,
  criado_em timestamptz not null default now(),
  usuario_id uuid
);
create index os_fotos_os on public.os_fotos (os_id);
alter table public.os_fotos enable row level security;
create policy os_fotos_org on public.os_fotos for select using (organizacao_id in (select public.minhas_organizacoes()));
create policy os_fotos_tecnico on public.os_fotos for select using (os_id in (select public.minhas_os()));
revoke all on public.os_fotos from public, anon, authenticated;
grant select on public.os_fotos to authenticated;

create function public.registrar_foto_os(p_os_id uuid, p_caminho text)
returns public.os_fotos
language plpgsql
security definer
set search_path = public
as $$
declare os public.ordens_servico%rowtype; f public.os_fotos%rowtype;
begin
  select * into os from public.ordens_servico where id = p_os_id;
  if not found then raise exception 'Chamado não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro_ou_tecnico_os(os);
  if os.status = 'cancelado' then raise exception 'Chamado cancelado não recebe fotos.' using errcode = 'check_violation'; end if;
  if (select count(*) from public.os_fotos where os_id = p_os_id) >= 3 then
    raise exception 'Máximo de 3 fotos por chamado.' using errcode = 'check_violation';
  end if;
  if p_caminho is null or p_caminho not like 'os/' || p_os_id || '/%' then
    raise exception 'Caminho da foto inválido.' using errcode = 'check_violation';
  end if;
  insert into public.os_fotos (organizacao_id, os_id, caminho, usuario_id) values (os.organizacao_id, p_os_id, p_caminho, auth.uid()) returning * into f;
  return f;
end;
$$;
revoke all on function public.registrar_foto_os(uuid, text) from public, anon;
grant execute on function public.registrar_foto_os(uuid, text) to authenticated;

-- bucket e políticas do Storage (só no Supabase real; o Postgres local não tem storage)
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public) values ('os-fotos', 'os-fotos', false) on conflict (id) do nothing;
    execute $pol$create policy os_fotos_upload on storage.objects for insert to authenticated
      with check (bucket_id = 'os-fotos' and (
        exists (select 1 from public.organizacao_membros m where m.usuario_id = auth.uid())
        or exists (select 1 from public.tecnicos t where t.usuario_id = auth.uid() and t.ativo)))$pol$;
    execute $pol$create policy os_fotos_leitura on storage.objects for select to authenticated
      using (bucket_id = 'os-fotos' and (
        exists (select 1 from public.organizacao_membros m where m.usuario_id = auth.uid())
        or exists (select 1 from public.tecnicos t where t.usuario_id = auth.uid() and t.ativo)))$pol$;
  end if;
end;
$$;
