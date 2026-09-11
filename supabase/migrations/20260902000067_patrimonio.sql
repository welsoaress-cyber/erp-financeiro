-- =============================================================================
-- 0067 · Etapa 41 — Patrimônio (bens individuais, fora do estoque de consumo)
-- =============================================================================
-- Consumível continua em estoque_itens (saldo, custo médio, alertas).
-- Patrimônio é bem individual: estante, fusionadora, power meter, nobreak…
-- Compra única, valor de aquisição próprio, número de patrimônio e série,
-- localização (POP, veículo, casa do técnico), estado de conservação e NF.
-- Nunca entra em alerta de reposição. Movimentos: transferência de local e
-- baixa (venda/perda/descarte), com histórico imutável — inventário completo
-- para venda da operação, seguro e prova de propriedade.
-- =============================================================================

create type public.estado_patrimonio as enum ('novo', 'bom', 'regular', 'ruim');
create type public.status_patrimonio as enum ('ativo', 'vendido', 'perdido', 'descartado');

create table public.patrimonios (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id uuid not null references public.negocios (id) on delete restrict,
  numero int not null, -- nº de patrimônio sequencial por organização (PAT-001…)
  nome text not null check (char_length(btrim(nome)) between 2 and 120),
  numero_serie text check (numero_serie is null or char_length(numero_serie) <= 60),
  valor_aquisicao numeric not null default 0 check (valor_aquisicao >= 0),
  data_aquisicao date not null default current_date,
  nota_fiscal text check (nota_fiscal is null or char_length(nota_fiscal) <= 60),
  localizacao text not null check (char_length(btrim(localizacao)) between 2 and 100),
  estado public.estado_patrimonio not null default 'bom',
  status public.status_patrimonio not null default 'ativo',
  lancamento_id uuid references public.lancamentos (id) on delete set null,
  observacao text check (observacao is null or char_length(observacao) <= 300),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (organizacao_id, numero)
);
create index patrimonios_negocio_idx on public.patrimonios (negocio_id, status);
comment on table public.patrimonios is 'Bens patrimoniais individuais (fora do estoque de consumo).';

create table public.patrimonio_historico (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  patrimonio_id uuid not null references public.patrimonios (id) on delete restrict,
  evento text not null check (evento in ('cadastro', 'transferencia', 'baixa', 'estado')),
  detalhe text not null check (char_length(detalhe) <= 300),
  usuario_id uuid,
  criado_em timestamptz not null default now()
);
create index patrimonio_historico_idx on public.patrimonio_historico (patrimonio_id, criado_em desc);

alter table public.patrimonios enable row level security;
alter table public.patrimonio_historico enable row level security;
create policy patrimonios_select on public.patrimonios for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));
create policy patrimonios_insert on public.patrimonios for insert to authenticated
  with check (organizacao_id in (select public.minhas_organizacoes()));
create policy patrimonios_update on public.patrimonios for update to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));
create policy patrimonio_historico_select on public.patrimonio_historico for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));

-- número sequencial por organização + histórico de cadastro
create or replace function public.tg_patrimonios_ins()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.numero is null or new.numero = 0 then
    select coalesce(max(numero), 0) + 1 into new.numero
      from public.patrimonios where organizacao_id = new.organizacao_id;
  end if;
  return new;
end; $$;
create trigger patrimonios_a_ins before insert on public.patrimonios
  for each row execute function public.tg_patrimonios_ins();

-- proteções: baixado não edita; local/estado/status mudam com histórico automático
create or replace function public.tg_patrimonios_upd()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status <> 'ativo' then
    raise exception 'Bem baixado (%) não pode ser alterado.', old.status using errcode = 'check_violation';
  end if;
  if new.organizacao_id <> old.organizacao_id or new.numero <> old.numero then
    raise exception 'Organização e número do patrimônio não mudam.' using errcode = 'check_violation';
  end if;
  if new.localizacao is distinct from old.localizacao then
    insert into public.patrimonio_historico (organizacao_id, patrimonio_id, evento, detalhe, usuario_id)
    values (old.organizacao_id, old.id, 'transferencia', old.localizacao || ' → ' || new.localizacao, auth.uid());
  end if;
  if new.estado is distinct from old.estado then
    insert into public.patrimonio_historico (organizacao_id, patrimonio_id, evento, detalhe, usuario_id)
    values (old.organizacao_id, old.id, 'estado', old.estado || ' → ' || new.estado, auth.uid());
  end if;
  if new.status is distinct from old.status then
    insert into public.patrimonio_historico (organizacao_id, patrimonio_id, evento, detalhe, usuario_id)
    values (old.organizacao_id, old.id, 'baixa', 'Baixa: ' || new.status || coalesce(' — ' || new.observacao, ''), auth.uid());
  end if;
  new.atualizado_em := now();
  return new;
end; $$;
create trigger patrimonios_b_upd before update on public.patrimonios
  for each row execute function public.tg_patrimonios_upd();

create or replace function public.tg_patrimonios_pos_ins()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.patrimonio_historico (organizacao_id, patrimonio_id, evento, detalhe, usuario_id)
  values (new.organizacao_id, new.id, 'cadastro', 'Cadastrado em ' || new.localizacao, auth.uid());
  return new;
end; $$;
create trigger patrimonios_c_pos_ins after insert on public.patrimonios
  for each row execute function public.tg_patrimonios_pos_ins();

-- histórico imutável
create or replace function public.tg_patrimonio_hist_imutavel()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'Histórico de patrimônio é imutável.' using errcode = 'check_violation';
end; $$;
create trigger patrimonio_historico_imutavel before update or delete on public.patrimonio_historico
  for each row execute function public.tg_patrimonio_hist_imutavel();

create trigger patrimonios_auditoria after insert or update or delete on public.patrimonios
  for each row execute function public.tg_auditoria();

revoke all on public.patrimonios from anon;
revoke all on public.patrimonio_historico from anon;
revoke delete on public.patrimonios from authenticated;
revoke insert, update, delete on public.patrimonio_historico from authenticated;
