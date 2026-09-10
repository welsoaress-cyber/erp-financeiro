-- =============================================================================
-- 0047 · Etapa 27A — Mapeamento FTTH: CTOs, portas e histórico
-- =============================================================================
-- CTOs (caixas de terminação óptica) por negócio, portas geradas no cadastro,
-- vínculo cliente↔porta amarrado a um CONTRATO ativo do mesmo negócio, uma
-- porta por cliente, reserva com cliente, liberação/troca deixam a porta com
-- "drop disponível", defeito bloqueia ocupação mas mantém o cliente. Todo
-- movimento de porta passa pelo motor e é gravado no histórico.
-- =============================================================================

create type public.status_cto as enum ('ativa', 'manutencao', 'desativada');
create type public.status_porta as enum ('livre', 'ocupada', 'reservada');
create type public.evento_porta as enum ('ocupacao', 'reserva', 'liberacao', 'troca', 'defeito', 'reparo');

create table public.ctos (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  codigo text not null check (char_length(btrim(codigo)) between 2 and 20),
  endereco text check (endereco is null or char_length(endereco) <= 200),
  referencia text check (referencia is null or char_length(referencia) <= 120),
  latitude numeric(9,6) not null check (latitude between -90 and 90),
  longitude numeric(9,6) not null check (longitude between -180 and 180),
  quantidade_portas smallint not null check (quantidade_portas between 1 and 64),
  splitter text check (splitter is null or splitter ~ '^1x(2|4|8|16|32|64)$'),
  status public.status_cto not null default 'ativa',
  observacao text check (observacao is null or char_length(observacao) <= 500),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (organizacao_id, codigo)
);
create trigger ctos_atualizado before update on public.ctos for each row execute function public.tg_atualizado_em();

create table public.cto_portas (
  id uuid primary key default gen_random_uuid(),
  cto_id uuid not null references public.ctos (id),
  organizacao_id uuid not null references public.organizacoes (id),
  numero smallint not null check (numero between 1 and 64),
  status public.status_porta not null default 'livre',
  defeito boolean not null default false,
  drop_disponivel boolean not null default false,
  pessoa_id uuid references public.pessoas (id),
  contrato_id uuid references public.contratos (id),
  data_ocupacao date,
  observacao text check (observacao is null or char_length(observacao) <= 300),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (cto_id, numero),
  check ((status = 'livre') = (pessoa_id is null)),
  check (pessoa_id is not null or contrato_id is null)
);
create trigger cto_portas_atualizado before update on public.cto_portas for each row execute function public.tg_atualizado_em();
-- uma porta por cliente (ocupada ou reservada)
create unique index cto_portas_pessoa_unica on public.cto_portas (pessoa_id) where pessoa_id is not null;

create table public.cto_historico (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  cto_id uuid not null references public.ctos (id),
  porta_id uuid not null references public.cto_portas (id),
  evento public.evento_porta not null,
  pessoa_id uuid references public.pessoas (id),
  contrato_id uuid references public.contratos (id),
  observacao text,
  usuario_id uuid,
  criado_em timestamptz not null default now()
);
create index cto_historico_cto on public.cto_historico (cto_id, criado_em desc);

-- portas e histórico só pelo motor; CTO tem CRUD direto (com trigger de portas)
create or replace function public.tg_ftth_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('erp.motor', true), '') <> 'on' then
    raise exception 'Portas e histórico de CTO são gravados pelo motor (vincular/liberar/trocar).' using errcode = 'insufficient_privilege';
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function public.tg_ftth_protecao() from public, anon, authenticated;
create trigger cto_portas_protecao before insert or update or delete on public.cto_portas for each row execute function public.tg_ftth_protecao();
create trigger cto_historico_protecao before insert or update or delete on public.cto_historico for each row execute function public.tg_ftth_protecao();

-- criar/ajustar CTO gera as portas; reduzir só se as excedentes estiverem livres
-- security definer: a redução apaga portas livres excedentes sem grant de DELETE para authenticated
create or replace function public.tg_ctos_portas()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.codigo := upper(btrim(new.codigo));
  perform set_config('erp.motor', 'on', true);
  if tg_op = 'UPDATE' then
    if new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id then
      raise exception 'A CTO não pode mudar de negócio.' using errcode = 'check_violation';
    end if;
    if new.quantidade_portas < old.quantidade_portas then
      if exists (select 1 from public.cto_portas p where p.cto_id = new.id and p.numero > new.quantidade_portas and p.status <> 'livre') then
        raise exception 'Há portas ocupadas/reservadas acima da nova quantidade: libere antes de reduzir.' using errcode = 'check_violation';
      end if;
      delete from public.cto_portas p where p.cto_id = new.id and p.numero > new.quantidade_portas;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.tg_ctos_portas() from public, anon, authenticated;
create trigger ctos_b_portas before insert or update on public.ctos for each row execute function public.tg_ctos_portas();

create or replace function public.tg_ctos_portas_depois()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform set_config('erp.motor', 'on', true);
  insert into public.cto_portas (cto_id, organizacao_id, numero)
  select new.id, new.organizacao_id, n
    from generate_series(1, new.quantidade_portas) n
   where not exists (select 1 from public.cto_portas p where p.cto_id = new.id and p.numero = n);
  return new;
end;
$$;
revoke all on function public.tg_ctos_portas_depois() from public, anon, authenticated;
create trigger ctos_c_gerar_portas after insert or update of quantidade_portas on public.ctos for each row execute function public.tg_ctos_portas_depois();

-- -----------------------------------------------------------------------------
-- Motor: vincular / liberar / trocar / defeito
-- -----------------------------------------------------------------------------
create function public.vincular_porta_cto(p_porta_id uuid, p_pessoa_id uuid, p_contrato_id uuid, p_reservar boolean default false, p_observacao text default null)
returns public.cto_portas
language plpgsql
security definer
set search_path = public
as $$
declare pt public.cto_portas%rowtype; c public.ctos%rowtype; ct public.contratos%rowtype; pe public.pessoas%rowtype;
begin
  select * into pt from public.cto_portas where id = p_porta_id;
  if not found then raise exception 'Porta não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(pt.organizacao_id);
  select * into c from public.ctos where id = pt.cto_id;
  if c.status <> 'ativa' then raise exception 'CTO % não está ativa.', c.codigo using errcode = 'check_violation'; end if;
  if pt.defeito then raise exception 'Porta com defeito não pode ser ocupada.' using errcode = 'check_violation'; end if;
  if pt.status <> 'livre' and not (pt.status = 'reservada' and pt.pessoa_id = p_pessoa_id) then
    raise exception 'Porta % já está % .', pt.numero, pt.status using errcode = 'check_violation';
  end if;
  select * into pe from public.pessoas where id = p_pessoa_id;
  if not found or pe.organizacao_id <> pt.organizacao_id then raise exception 'Pessoa inválida.' using errcode = 'check_violation'; end if;
  select * into ct from public.contratos where id = p_contrato_id;
  if not found or ct.pessoa_id <> p_pessoa_id or ct.negocio_id <> c.negocio_id then
    raise exception 'Contrato inválido: precisa ser do cliente e do negócio da CTO.' using errcode = 'check_violation';
  end if;
  if ct.status <> 'ativo' then raise exception 'O contrato não está ativo.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.cto_portas
     set status = case when p_reservar then 'reservada' else 'ocupada' end::public.status_porta,
         pessoa_id = p_pessoa_id, contrato_id = p_contrato_id,
         data_ocupacao = case when p_reservar then null else current_date end,
         drop_disponivel = false, observacao = coalesce(p_observacao, observacao)
   where id = p_porta_id returning * into pt;
  insert into public.cto_historico (organizacao_id, cto_id, porta_id, evento, pessoa_id, contrato_id, observacao, usuario_id)
  values (pt.organizacao_id, pt.cto_id, pt.id, case when p_reservar then 'reserva' else 'ocupacao' end::public.evento_porta, p_pessoa_id, p_contrato_id, p_observacao, auth.uid());
  return pt;
end;
$$;

create function public.liberar_porta_cto(p_porta_id uuid, p_observacao text default null)
returns public.cto_portas
language plpgsql
security definer
set search_path = public
as $$
declare pt public.cto_portas%rowtype;
begin
  select * into pt from public.cto_portas where id = p_porta_id;
  if not found then raise exception 'Porta não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(pt.organizacao_id);
  if pt.status = 'livre' then raise exception 'A porta já está livre.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  insert into public.cto_historico (organizacao_id, cto_id, porta_id, evento, pessoa_id, contrato_id, observacao, usuario_id)
  values (pt.organizacao_id, pt.cto_id, pt.id, 'liberacao', pt.pessoa_id, pt.contrato_id, p_observacao, auth.uid());
  update public.cto_portas
     set status = 'livre', pessoa_id = null, contrato_id = null, data_ocupacao = null,
         drop_disponivel = true, observacao = coalesce(p_observacao, 'Drop disponível para utilização')
   where id = p_porta_id returning * into pt;
  return pt;
end;
$$;

create function public.trocar_porta_cto(p_porta_origem uuid, p_porta_destino uuid, p_observacao text default null)
returns public.cto_portas
language plpgsql
security definer
set search_path = public
as $$
declare o public.cto_portas%rowtype; d public.cto_portas%rowtype; cd public.ctos%rowtype; co public.ctos%rowtype;
begin
  select * into o from public.cto_portas where id = p_porta_origem;
  if not found or o.status = 'livre' then raise exception 'Porta de origem sem cliente.' using errcode = 'check_violation'; end if;
  perform public.exigir_membro(o.organizacao_id);
  select * into d from public.cto_portas where id = p_porta_destino;
  if not found or d.organizacao_id <> o.organizacao_id then raise exception 'Porta de destino inválida.' using errcode = 'check_violation'; end if;
  if d.status <> 'livre' then raise exception 'Porta de destino não está livre.' using errcode = 'check_violation'; end if;
  if d.defeito then raise exception 'Porta de destino com defeito.' using errcode = 'check_violation'; end if;
  select * into cd from public.ctos where id = d.cto_id;
  select * into co from public.ctos where id = o.cto_id;
  if cd.status <> 'ativa' then raise exception 'CTO de destino não está ativa.' using errcode = 'check_violation'; end if;
  if cd.negocio_id <> co.negocio_id then raise exception 'A troca deve ser entre CTOs do mesmo negócio.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  insert into public.cto_historico (organizacao_id, cto_id, porta_id, evento, pessoa_id, contrato_id, observacao, usuario_id)
  values (o.organizacao_id, o.cto_id, o.id, 'troca', o.pessoa_id, o.contrato_id, coalesce(p_observacao, 'Saída para ' || cd.codigo || ' porta ' || d.numero), auth.uid());
  update public.cto_portas
     set status = 'livre', pessoa_id = null, contrato_id = null, data_ocupacao = null,
         drop_disponivel = true, observacao = 'Drop disponível para utilização'
   where id = o.id;
  update public.cto_portas
     set status = o.status, pessoa_id = o.pessoa_id, contrato_id = o.contrato_id,
         data_ocupacao = coalesce(o.data_ocupacao, current_date), drop_disponivel = false
   where id = d.id returning * into d;
  insert into public.cto_historico (organizacao_id, cto_id, porta_id, evento, pessoa_id, contrato_id, observacao, usuario_id)
  values (d.organizacao_id, d.cto_id, d.id, 'troca', d.pessoa_id, d.contrato_id, coalesce(p_observacao, 'Entrada vinda de ' || co.codigo || ' porta ' || o.numero), auth.uid());
  return d;
end;
$$;

create function public.defeito_porta_cto(p_porta_id uuid, p_defeito boolean, p_observacao text default null)
returns public.cto_portas
language plpgsql
security definer
set search_path = public
as $$
declare pt public.cto_portas%rowtype;
begin
  select * into pt from public.cto_portas where id = p_porta_id;
  if not found then raise exception 'Porta não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(pt.organizacao_id);
  perform set_config('erp.motor', 'on', true);
  update public.cto_portas set defeito = p_defeito, observacao = coalesce(p_observacao, observacao) where id = p_porta_id returning * into pt;
  insert into public.cto_historico (organizacao_id, cto_id, porta_id, evento, pessoa_id, contrato_id, observacao, usuario_id)
  values (pt.organizacao_id, pt.cto_id, pt.id, case when p_defeito then 'defeito' else 'reparo' end::public.evento_porta, pt.pessoa_id, pt.contrato_id, p_observacao, auth.uid());
  return pt;
end;
$$;

-- Ocupação consolidada por CTO (alertas ao vivo)
create or replace view public.vw_ctos_ocupacao
with (security_invoker = true) as
select c.*,
       count(p.id) filter (where p.status = 'ocupada') as ocupadas,
       count(p.id) filter (where p.status = 'reservada') as reservadas,
       count(p.id) filter (where p.status = 'livre' and not p.defeito) as livres,
       count(p.id) filter (where p.defeito) as com_defeito,
       count(p.id) filter (where p.drop_disponivel and p.status = 'livre') as drops_disponiveis
  from public.ctos c
  left join public.cto_portas p on p.cto_id = c.id
 group by c.id;

-- -----------------------------------------------------------------------------
-- RLS e permissões
-- -----------------------------------------------------------------------------
alter table public.ctos enable row level security;
alter table public.cto_portas enable row level security;
alter table public.cto_historico enable row level security;
create policy ctos_org on public.ctos using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy cto_portas_org on public.cto_portas using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy cto_historico_org on public.cto_historico using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.ctos, public.cto_portas, public.cto_historico, public.vw_ctos_ocupacao from public, anon, authenticated;
grant select, insert, update on public.ctos to authenticated;
grant select, insert, update on public.cto_portas, public.cto_historico to authenticated;
grant select on public.vw_ctos_ocupacao to authenticated;

revoke all on function public.vincular_porta_cto(uuid, uuid, uuid, boolean, text), public.liberar_porta_cto(uuid, text),
  public.trocar_porta_cto(uuid, uuid, text), public.defeito_porta_cto(uuid, boolean, text) from public, anon;
grant execute on function public.vincular_porta_cto(uuid, uuid, uuid, boolean, text), public.liberar_porta_cto(uuid, text),
  public.trocar_porta_cto(uuid, uuid, text), public.defeito_porta_cto(uuid, boolean, text) to authenticated;
