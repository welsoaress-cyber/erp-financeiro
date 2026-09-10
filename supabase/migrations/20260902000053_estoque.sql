-- =============================================================================
-- 0053 · Etapa 28A — Estoque: categorias, itens e movimentações
-- =============================================================================
-- Estoque por negócio (Servnet primeiro; o modelo serve a qualquer negócio).
-- Quantidade e custo médio ponderado são derivados das MOVIMENTAÇÕES, que são
-- imutáveis (auditoria) e gravadas só pelo motor: entrada_estoque (compra/
-- devolução, recalcula o custo médio), saida_estoque (instalação/perda, usa o
-- custo médio e bloqueia saída maior que o disponível) e ajuste_estoque
-- (inventário: define a quantidade, registrando o delta). A despesa da compra
-- é criada pelo app via criar_lancamento (pagamento misto: um lançamento por
-- forma de pagamento) e amarrada às entradas por lancamento_id.
-- =============================================================================

create type public.tipo_movimentacao_estoque as enum ('entrada', 'saida', 'ajuste');
create type public.origem_movimentacao_estoque as enum ('compra', 'instalacao', 'devolucao', 'ajuste', 'perda', 'inventario');

create table public.estoque_categorias (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  nome text not null check (char_length(btrim(nome)) between 2 and 60),
  descricao text check (descricao is null or char_length(descricao) <= 200),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (negocio_id, nome)
);
create trigger estoque_categorias_atualizado before update on public.estoque_categorias for each row execute function public.tg_atualizado_em();

create table public.estoque_itens (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  categoria_id uuid not null references public.estoque_categorias (id),
  codigo text not null check (codigo ~ '^[A-Za-z0-9._-]{2,20}$'),
  nome text not null check (char_length(btrim(nome)) between 2 and 80),
  descricao text check (descricao is null or char_length(descricao) <= 300),
  unidade_medida text not null default 'unidade' check (unidade_medida in ('unidade', 'metro', 'caixa', 'pacote', 'rolo', 'par')),
  marca text check (marca is null or char_length(marca) <= 60),
  modelo text check (modelo is null or char_length(modelo) <= 60),
  valor_custo numeric(12,4) not null default 0 check (valor_custo >= 0),
  valor_venda numeric(12,2) check (valor_venda is null or valor_venda >= 0),
  quantidade_atual numeric(12,2) not null default 0 check (quantidade_atual >= 0),
  quantidade_minima numeric(12,2) not null default 0 check (quantidade_minima >= 0),
  quantidade_maxima numeric(12,2) check (quantidade_maxima is null or quantidade_maxima >= 0),
  localizacao text check (localizacao is null or char_length(localizacao) <= 100),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (organizacao_id, codigo)
);
create trigger estoque_itens_atualizado before update on public.estoque_itens for each row execute function public.tg_atualizado_em();

create table public.estoque_movimentacoes (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  item_id uuid not null references public.estoque_itens (id),
  tipo public.tipo_movimentacao_estoque not null,
  origem public.origem_movimentacao_estoque not null,
  quantidade numeric(12,2) not null,
  valor_unitario numeric(12,4) not null default 0,
  valor_total numeric(12,2) not null default 0,
  data date not null default current_date,
  pessoa_id uuid references public.pessoas (id),
  contrato_id uuid references public.contratos (id),
  lancamento_id uuid references public.lancamentos (id),
  observacao text check (observacao is null or char_length(observacao) <= 300),
  usuario_id uuid,
  criado_em timestamptz not null default now()
);
create index estoque_mov_item on public.estoque_movimentacoes (item_id, data desc);
create index estoque_mov_contrato on public.estoque_movimentacoes (contrato_id) where contrato_id is not null;

-- quantidade/custo do item e movimentações: só pelo motor; movimentação nunca muda nem some
create or replace function public.tg_estoque_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'estoque_movimentacoes' and tg_op in ('UPDATE', 'DELETE') then
    raise exception 'Movimentação de estoque é imutável: corrija com um ajuste.' using errcode = 'check_violation';
  end if;
  if coalesce(current_setting('erp.motor', true), '') <> 'on' then
    if tg_table_name = 'estoque_movimentacoes' then
      raise exception 'Movimentações são gravadas pelo motor (entrada/saída/ajuste de estoque).' using errcode = 'insufficient_privilege';
    end if;
    if tg_op = 'UPDATE' and (new.quantidade_atual <> old.quantidade_atual or new.valor_custo <> old.valor_custo) then
      raise exception 'Quantidade e custo médio são derivados das movimentações.' using errcode = 'check_violation';
    end if;
    if tg_op = 'INSERT' and new.quantidade_atual <> 0 then
      raise exception 'Item nasce zerado: lance a quantidade por um ajuste de inventário.' using errcode = 'check_violation';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function public.tg_estoque_protecao() from public, anon, authenticated;
create trigger estoque_itens_protecao before insert or update on public.estoque_itens for each row execute function public.tg_estoque_protecao();
create trigger estoque_mov_protecao before insert or update or delete on public.estoque_movimentacoes for each row execute function public.tg_estoque_protecao();

-- -----------------------------------------------------------------------------
-- Motor
-- -----------------------------------------------------------------------------
create function public.entrada_estoque(
  p_item_id uuid, p_quantidade numeric, p_valor_total numeric, p_data date default current_date,
  p_origem text default 'compra', p_lancamento_id uuid default null, p_observacao text default null
)
returns public.estoque_movimentacoes
language plpgsql
security definer
set search_path = public
as $$
declare it public.estoque_itens%rowtype; m public.estoque_movimentacoes%rowtype; v_unit numeric;
begin
  select * into it from public.estoque_itens where id = p_item_id;
  if not found then raise exception 'Item não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(it.organizacao_id);
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade da entrada deve ser maior que zero.' using errcode = 'check_violation'; end if;
  if p_valor_total is null or p_valor_total < 0 then raise exception 'Valor da entrada inválido.' using errcode = 'check_violation'; end if;
  if p_origem not in ('compra', 'devolucao', 'inventario') then raise exception 'Origem de entrada inválida.' using errcode = 'check_violation'; end if;
  v_unit := round(p_valor_total / p_quantidade, 4);
  perform set_config('erp.motor', 'on', true);
  -- custo médio ponderado
  update public.estoque_itens
     set valor_custo = case when quantidade_atual + p_quantidade > 0
                            then round((quantidade_atual * valor_custo + p_valor_total) / (quantidade_atual + p_quantidade), 4)
                            else valor_custo end,
         quantidade_atual = quantidade_atual + p_quantidade
   where id = p_item_id;
  insert into public.estoque_movimentacoes (organizacao_id, negocio_id, item_id, tipo, origem, quantidade, valor_unitario, valor_total, data, lancamento_id, observacao, usuario_id)
  values (it.organizacao_id, it.negocio_id, p_item_id, 'entrada', p_origem::public.origem_movimentacao_estoque, p_quantidade, v_unit, round(p_valor_total, 2), p_data, p_lancamento_id, p_observacao, auth.uid())
  returning * into m;
  return m;
end;
$$;

create function public.saida_estoque(
  p_item_id uuid, p_quantidade numeric, p_origem text default 'perda', p_data date default current_date,
  p_pessoa_id uuid default null, p_contrato_id uuid default null, p_observacao text default null
)
returns public.estoque_movimentacoes
language plpgsql
security definer
set search_path = public
as $$
declare it public.estoque_itens%rowtype; m public.estoque_movimentacoes%rowtype;
begin
  select * into it from public.estoque_itens where id = p_item_id;
  if not found then raise exception 'Item não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(it.organizacao_id);
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade da saída deve ser maior que zero.' using errcode = 'check_violation'; end if;
  if p_origem not in ('instalacao', 'perda') then raise exception 'Origem de saída inválida.' using errcode = 'check_violation'; end if;
  if p_quantidade > it.quantidade_atual then
    raise exception 'Saída maior que o estoque disponível (% %).', it.quantidade_atual, it.unidade_medida using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.estoque_itens set quantidade_atual = quantidade_atual - p_quantidade where id = p_item_id;
  insert into public.estoque_movimentacoes (organizacao_id, negocio_id, item_id, tipo, origem, quantidade, valor_unitario, valor_total, data, pessoa_id, contrato_id, observacao, usuario_id)
  values (it.organizacao_id, it.negocio_id, p_item_id, 'saida', p_origem::public.origem_movimentacao_estoque, p_quantidade, it.valor_custo, round(p_quantidade * it.valor_custo, 2), p_data, p_pessoa_id, p_contrato_id, p_observacao, auth.uid())
  returning * into m;
  return m;
end;
$$;

create function public.ajuste_estoque(p_item_id uuid, p_quantidade_nova numeric, p_valor_total numeric default null, p_observacao text default null)
returns public.estoque_movimentacoes
language plpgsql
security definer
set search_path = public
as $$
declare it public.estoque_itens%rowtype; m public.estoque_movimentacoes%rowtype; v_delta numeric;
begin
  select * into it from public.estoque_itens where id = p_item_id;
  if not found then raise exception 'Item não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(it.organizacao_id);
  if p_quantidade_nova is null or p_quantidade_nova < 0 then raise exception 'Quantidade do ajuste inválida.' using errcode = 'check_violation'; end if;
  v_delta := p_quantidade_nova - it.quantidade_atual;
  perform set_config('erp.motor', 'on', true);
  update public.estoque_itens
     set quantidade_atual = p_quantidade_nova,
         valor_custo = case when p_valor_total is not null and p_quantidade_nova > 0
                            then round(p_valor_total / p_quantidade_nova, 4) else valor_custo end
   where id = p_item_id;
  insert into public.estoque_movimentacoes (organizacao_id, negocio_id, item_id, tipo, origem, quantidade, valor_unitario, valor_total, observacao, usuario_id)
  values (it.organizacao_id, it.negocio_id, p_item_id, 'ajuste', case when p_valor_total is not null then 'inventario' else 'ajuste' end::public.origem_movimentacao_estoque,
          v_delta, it.valor_custo, round(coalesce(p_valor_total, v_delta * it.valor_custo), 2), coalesce(p_observacao, 'Ajuste de inventário'), auth.uid())
  returning * into m;
  return m;
end;
$$;

revoke all on function public.entrada_estoque(uuid, numeric, numeric, date, text, uuid, text),
  public.saida_estoque(uuid, numeric, text, date, uuid, uuid, text),
  public.ajuste_estoque(uuid, numeric, numeric, text) from public, anon;
grant execute on function public.entrada_estoque(uuid, numeric, numeric, date, text, uuid, text),
  public.saida_estoque(uuid, numeric, text, date, uuid, uuid, text),
  public.ajuste_estoque(uuid, numeric, numeric, text) to authenticated;

-- categorias padrão para os negócios existentes
insert into public.estoque_categorias (organizacao_id, negocio_id, nome)
select n.organizacao_id, n.id, c.nome
  from public.negocios n
 cross join (values ('Cabos'), ('Conectores'), ('Equipamentos'), ('Ferramentas'), ('Fixação')) c (nome)
 where n.ativo
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- RLS e permissões
-- -----------------------------------------------------------------------------
alter table public.estoque_categorias enable row level security;
alter table public.estoque_itens enable row level security;
alter table public.estoque_movimentacoes enable row level security;
create policy estoque_categorias_org on public.estoque_categorias using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy estoque_itens_org on public.estoque_itens using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy estoque_mov_org on public.estoque_movimentacoes using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.estoque_categorias, public.estoque_itens, public.estoque_movimentacoes from public, anon, authenticated;
grant select, insert, update on public.estoque_categorias, public.estoque_itens to authenticated;
grant select, insert on public.estoque_movimentacoes to authenticated;
