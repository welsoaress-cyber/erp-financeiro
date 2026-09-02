-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0007: PESSOAS E VÍNCULOS (Etapa 6B)
-- Cadastro único de pessoas (física/jurídica) no núcleo; vínculo pessoa ×
-- negócio × papel; pessoa_id opcional em lançamentos.
-- =============================================================================

create type public.tipo_pessoa  as enum ('fisica', 'juridica');
create type public.papel_vinculo as enum ('cliente', 'fornecedor', 'parceiro', 'outro');

-- Validação de CPF (11 dígitos) e CNPJ (14 dígitos) pelos dígitos verificadores.
create or replace function public.documento_valido(p_doc text)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  d int[]; s int; i int; dv1 int; dv2 int;
begin
  if p_doc is null or p_doc !~ '^[0-9]+$' then return false; end if;
  if p_doc ~ '^(\d)\1+$' then return false; end if;
  d := array(select (regexp_split_to_table(p_doc, ''))::int);
  if length(p_doc) = 11 then
    s := 0; for i in 1..9 loop s := s + d[i] * (11 - i); end loop;
    dv1 := (s * 10) % 11; if dv1 = 10 then dv1 := 0; end if;
    s := 0; for i in 1..10 loop s := s + d[i] * (12 - i); end loop;
    dv2 := (s * 10) % 11; if dv2 = 10 then dv2 := 0; end if;
    return dv1 = d[10] and dv2 = d[11];
  elsif length(p_doc) = 14 then
    s := 0; for i in 1..12 loop s := s + d[i] * (case when i <= 4 then 6 - i else 14 - i end); end loop;
    dv1 := s % 11; dv1 := case when dv1 < 2 then 0 else 11 - dv1 end;
    s := 0; for i in 1..13 loop s := s + d[i] * (case when i <= 5 then 7 - i else 15 - i end); end loop;
    dv2 := s % 11; dv2 := case when dv2 < 2 then 0 else 11 - dv2 end;
    return dv1 = d[13] and dv2 = d[14];
  end if;
  return false;
end;
$$;

create table public.pessoas (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  tipo           public.tipo_pessoa not null default 'fisica',
  nome           text not null check (char_length(btrim(nome)) between 2 and 120),
  documento      text check (documento is null or public.documento_valido(documento)),
  email          text check (email is null or (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 120)),
  telefone       text check (telefone is null or telefone ~ '^[0-9]{10,13}$'),
  observacao     text check (observacao is null or char_length(observacao) <= 500),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  -- física ⇒ CPF (11); jurídica ⇒ CNPJ (14)
  check (documento is null or (tipo = 'fisica' and char_length(documento) = 11) or (tipo = 'juridica' and char_length(documento) = 14))
);
create index pessoas_organizacao_nome_idx on public.pessoas (organizacao_id, lower(nome));
create unique index pessoas_documento_unico_idx on public.pessoas (organizacao_id, documento) where documento is not null;
comment on table public.pessoas is 'Cadastro único de pessoas físicas/jurídicas da organização (clientes, fornecedores…). Documento só com dígitos.';

create table public.pessoa_negocio_vinculos (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  pessoa_id      uuid not null references public.pessoas (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  papel          public.papel_vinculo not null default 'cliente',
  ativo          boolean not null default true,
  desde          date not null default current_date,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (pessoa_id, negocio_id, papel)
);
create index vinculos_pessoa_idx on public.pessoa_negocio_vinculos (pessoa_id);
create index vinculos_negocio_idx on public.pessoa_negocio_vinculos (negocio_id, papel);
comment on table public.pessoa_negocio_vinculos is 'Relação pessoa × negócio × papel. Uma pessoa pode ser cliente de vários negócios.';

alter table public.lancamentos add column pessoa_id uuid references public.pessoas (id) on delete restrict;
create index lancamentos_pessoa_idx on public.lancamentos (pessoa_id);

-- -----------------------------------------------------------------------------
-- Proteções
-- -----------------------------------------------------------------------------
create or replace function public.tg_pessoas_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.nome := btrim(new.nome);
  new.email := nullif(lower(btrim(coalesce(new.email, ''))), '');
  new.documento := nullif(regexp_replace(coalesce(new.documento, ''), '[^0-9]', '', 'g'), '');
  new.telefone := nullif(regexp_replace(coalesce(new.telefone, ''), '[^0-9]', '', 'g'), '');
  if tg_op = 'UPDATE' then
    if new.organizacao_id <> old.organizacao_id then
      raise exception 'A pessoa não pode mudar de organização.' using errcode = 'check_violation';
    end if;
    if old.ativo and not new.ativo then
      if exists (select 1 from public.pessoa_negocio_vinculos v where v.pessoa_id = old.id and v.ativo) then
        raise exception 'A pessoa não pode ser inativada: possui vínculos ativos com negócios.' using errcode = 'check_violation';
      end if;
      if exists (select 1 from public.lancamentos l where l.pessoa_id = old.id and l.status = 'previsto') then
        raise exception 'A pessoa não pode ser inativada: possui lançamentos previstos pendentes.' using errcode = 'check_violation';
      end if;
    end if;
  end if;
  return new;
end;
$$;
create trigger pessoas_protecao before insert or update on public.pessoas for each row execute function public.tg_pessoas_protecao();
create trigger pessoas_atualizado_em before update on public.pessoas for each row execute function public.tg_atualizado_em();
create trigger pessoas_auditoria after insert or update or delete on public.pessoas for each row execute function public.tg_auditoria();

create or replace function public.tg_vinculos_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  p public.pessoas%rowtype;
begin
  select * into p from public.pessoas where id = new.pessoa_id;
  if not found or p.organizacao_id <> new.organizacao_id then
    raise exception 'Pessoa inválida.' using errcode = 'check_violation';
  end if;
  if tg_op = 'UPDATE' and (new.pessoa_id <> old.pessoa_id or new.organizacao_id <> old.organizacao_id) then
    raise exception 'O vínculo não pode mudar de pessoa ou organização.' using errcode = 'check_violation';
  end if;
  if new.ativo and (tg_op = 'INSERT' or not old.ativo) then
    if not p.ativo then
      raise exception 'A pessoa está inativa.' using errcode = 'check_violation';
    end if;
    perform public.validar_negocio(new.negocio_id, new.organizacao_id, true);
  else
    perform public.validar_negocio(new.negocio_id, new.organizacao_id, false);
  end if;
  return new;
end;
$$;
create trigger vinculos_protecao before insert or update on public.pessoa_negocio_vinculos for each row execute function public.tg_vinculos_protecao();
create trigger vinculos_atualizado_em before update on public.pessoa_negocio_vinculos for each row execute function public.tg_atualizado_em();
create trigger vinculos_auditoria after insert or update or delete on public.pessoa_negocio_vinculos for each row execute function public.tg_auditoria();

-- Lançamentos: pessoa da mesma organização; ativa ao vincular/trocar
create or replace function public.tg_lancamentos_pessoa()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  p public.pessoas%rowtype;
begin
  if new.pessoa_id is null then return new; end if;
  select * into p from public.pessoas where id = new.pessoa_id;
  if not found or p.organizacao_id <> new.organizacao_id then
    raise exception 'Pessoa inválida.' using errcode = 'check_violation';
  end if;
  if not p.ativo and (tg_op = 'INSERT' or new.pessoa_id is distinct from old.pessoa_id) then
    raise exception 'A pessoa está inativa.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger lancamentos_pessoa before insert or update on public.lancamentos for each row execute function public.tg_lancamentos_pessoa();

-- -----------------------------------------------------------------------------
-- Motor: p_pessoa_id (12º parâmetro)
-- -----------------------------------------------------------------------------
drop function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid);
drop function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid);

create function public.criar_lancamento(
  p_tipo text, p_descricao text, p_valor numeric, p_data_competencia date,
  p_data_vencimento date default null, p_data_efetivacao date default null,
  p_conta_id uuid default null, p_conta_destino_id uuid default null,
  p_categoria_id uuid default null, p_observacao text default null,
  p_negocio_id uuid default null, p_pessoa_id uuid default null
)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
  l public.lancamentos%rowtype;
begin
  select organizacao_id into v_org from public.contas where id = p_conta_id;
  perform public.exigir_membro(v_org);
  perform set_config('erp.motor', 'on', true);
  insert into public.lancamentos (
    organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao,
    status, conta_id, conta_destino_id, categoria_id, observacao, negocio_id, pessoa_id
  ) values (
    v_org, p_tipo::public.tipo_lancamento, btrim(p_descricao), p_valor, p_data_competencia,
    coalesce(p_data_vencimento, p_data_competencia), p_data_efetivacao,
    (case when p_data_efetivacao is null then 'previsto' else 'efetivado' end)::public.status_lancamento,
    p_conta_id, p_conta_destino_id, p_categoria_id, nullif(btrim(coalesce(p_observacao, '')), ''), p_negocio_id, p_pessoa_id
  ) returning * into l;
  perform public.gerar_movimentos(l.id);
  return l;
end;
$$;

create function public.atualizar_lancamento(
  p_id uuid, p_descricao text, p_valor numeric, p_data_competencia date,
  p_data_vencimento date default null, p_data_efetivacao date default null,
  p_conta_id uuid default null, p_conta_destino_id uuid default null,
  p_categoria_id uuid default null, p_observacao text default null,
  p_negocio_id uuid default null, p_pessoa_id uuid default null
)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  perform set_config('erp.motor', 'on', true);
  update public.lancamentos set
    descricao        = btrim(p_descricao),
    valor            = p_valor,
    data_competencia = p_data_competencia,
    data_vencimento  = coalesce(p_data_vencimento, p_data_competencia),
    data_efetivacao  = p_data_efetivacao,
    status           = (case when p_data_efetivacao is null then 'previsto' else 'efetivado' end)::public.status_lancamento,
    conta_id         = coalesce(p_conta_id, conta_id),
    conta_destino_id = case when tipo = 'transferencia' then coalesce(p_conta_destino_id, conta_destino_id) else null end,
    categoria_id     = case when tipo = 'transferencia' then null else coalesce(p_categoria_id, categoria_id) end,
    observacao       = nullif(btrim(coalesce(p_observacao, '')), ''),
    negocio_id       = p_negocio_id,
    pessoa_id        = p_pessoa_id
  where id = p_id
  returning * into l;
  perform public.gerar_movimentos(l.id);
  return l;
end;
$$;

-- -----------------------------------------------------------------------------
-- Privilégios e RLS
-- -----------------------------------------------------------------------------
revoke all on public.pessoas from anon, authenticated;
revoke all on public.pessoa_negocio_vinculos from anon, authenticated;
grant select, insert, update on public.pessoas to authenticated;
grant select, insert, update on public.pessoa_negocio_vinculos to authenticated;
revoke all on function public.documento_valido(text) from public, anon;
grant execute on function public.documento_valido(text) to authenticated;
revoke all on function public.tg_pessoas_protecao() from public, anon, authenticated;
revoke all on function public.tg_vinculos_protecao() from public, anon, authenticated;
revoke all on function public.tg_lancamentos_pessoa() from public, anon, authenticated;
revoke all on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid) from public, anon;
revoke all on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid) from public, anon;
grant execute on function public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid) to authenticated;
grant execute on function public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid) to authenticated;

alter table public.pessoas enable row level security;
alter table public.pessoa_negocio_vinculos enable row level security;

create policy pessoas_select on public.pessoas for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy pessoas_insert on public.pessoas for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy pessoas_update on public.pessoas for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));

create policy vinculos_select on public.pessoa_negocio_vinculos for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy vinculos_insert on public.pessoa_negocio_vinculos for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy vinculos_update on public.pessoa_negocio_vinculos for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
