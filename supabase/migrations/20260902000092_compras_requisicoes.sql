-- =============================================================================
-- 0092 · Etapa 55A — Módulo Compras: Requisição e Pedido (aprovação sempre)
-- =============================================================================
-- Fluxo formal de compras estilo ERP grande. Cadeia:
--   Requisição → Aprovação → Pedido → (Recebimento → Nota → Lançamento) [55B]
--
-- Regras:
-- - Qualquer membro pode CRIAR requisição; apenas o PROPRIETÁRIO da organização
--   aprova/rejeita. Solicitante pode ser o mesmo que o aprovador (o dono
--   trabalha sozinho hoje); a decisão fica registrada com timestamp e usuário.
-- - Requisição só carrega intenção (item + quantidade + destino + justificativa).
--   Valor unitário e fornecedor entram na aprovação: aprovar_requisicao cria o
--   Pedido com esses dados, marca a requisição como 'convertida' e amarra o
--   pedido à requisição.
-- - Numeração por negócio: requisicao.numero e compra.numero são sequenciais
--   (REQ-0001, PED-0001) via advisory-lock; não giram entre negócios.
-- - Compras NUNCA grava em lancamentos nem em estoque_itens. Recebimento e
--   integração com estoque/patrimônio/comodato/lançamento ficam para 55B.
-- =============================================================================

create type public.status_requisicao_compra as enum ('pendente', 'aprovada', 'rejeitada', 'convertida', 'cancelada');
create type public.status_pedido_compra as enum ('aberto', 'recebido_parcial', 'recebido', 'cancelado');
create type public.destino_compra_item as enum ('estoque', 'despesa', 'patrimonio', 'comodato', 'servico');

-- -----------------------------------------------------------------------------
-- Requisições
-- -----------------------------------------------------------------------------
create table public.compra_requisicoes (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  numero integer not null,
  solicitante_id uuid not null,                   -- auth.uid do solicitante
  justificativa text check (justificativa is null or char_length(justificativa) <= 500),
  status public.status_requisicao_compra not null default 'pendente',
  aprovador_id uuid,                              -- auth.uid do proprietário
  decidido_em timestamptz,
  motivo_rejeicao text check (motivo_rejeicao is null or char_length(motivo_rejeicao) <= 300),
  pedido_id uuid,                                 -- FK adicionada abaixo (após criar compras)
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (negocio_id, numero)
);
create trigger compra_requisicoes_atualizado before update on public.compra_requisicoes for each row execute function public.tg_atualizado_em();

create table public.compra_requisicao_itens (
  id uuid primary key default gen_random_uuid(),
  requisicao_id uuid not null references public.compra_requisicoes (id) on delete cascade,
  ordem integer not null,
  item_id uuid references public.estoque_itens (id),
  descricao text not null check (char_length(btrim(descricao)) between 2 and 140),
  quantidade numeric(12,2) not null check (quantidade > 0),
  destino public.destino_compra_item not null default 'estoque',
  observacao text check (observacao is null or char_length(observacao) <= 200),
  unique (requisicao_id, ordem)
);
create index compra_req_itens_req on public.compra_requisicao_itens (requisicao_id);

-- -----------------------------------------------------------------------------
-- Pedidos (compras)
-- -----------------------------------------------------------------------------
create table public.compras (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  requisicao_id uuid references public.compra_requisicoes (id),
  fornecedor_id uuid references public.pessoas (id),
  numero integer not null,
  data_pedido date not null default current_date,
  previsao_entrega date,
  condicao_pagamento text check (condicao_pagamento is null or char_length(condicao_pagamento) <= 60),
  valor_frete numeric(12,2) not null default 0 check (valor_frete >= 0),
  valor_desconto numeric(12,2) not null default 0 check (valor_desconto >= 0),
  observacao text check (observacao is null or char_length(observacao) <= 300),
  status public.status_pedido_compra not null default 'aberto',
  criado_por uuid,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (negocio_id, numero)
);
create trigger compras_atualizado before update on public.compras for each row execute function public.tg_atualizado_em();

create table public.compra_itens (
  id uuid primary key default gen_random_uuid(),
  compra_id uuid not null references public.compras (id) on delete cascade,
  item_id uuid references public.estoque_itens (id),
  descricao text not null check (char_length(btrim(descricao)) between 2 and 140),
  quantidade numeric(12,2) not null check (quantidade > 0),
  valor_unitario numeric(12,4) not null check (valor_unitario >= 0),
  destino public.destino_compra_item not null default 'estoque',
  categoria_id uuid references public.categorias (id),
  contrato_id uuid references public.contratos (id),
  quantidade_recebida numeric(12,2) not null default 0 check (quantidade_recebida >= 0),
  observacao text check (observacao is null or char_length(observacao) <= 200)
);
create index compra_itens_compra on public.compra_itens (compra_id);

alter table public.compra_requisicoes add constraint compra_requisicoes_pedido_fk foreign key (pedido_id) references public.compras (id);

-- -----------------------------------------------------------------------------
-- View: totais de pedido (derivados)
-- -----------------------------------------------------------------------------
create view public.vw_compras_totais with (security_invoker = true) as
select c.id as compra_id,
       c.organizacao_id,
       coalesce(sum(i.quantidade * i.valor_unitario), 0) as total_itens,
       coalesce(sum(i.quantidade_recebida * i.valor_unitario), 0) as total_recebido,
       coalesce(sum(i.quantidade * i.valor_unitario), 0) + c.valor_frete - c.valor_desconto as total_final
  from public.compras c
  left join public.compra_itens i on i.compra_id = c.id
 group by c.id, c.organizacao_id, c.valor_frete, c.valor_desconto;
grant select on public.vw_compras_totais to authenticated;

-- -----------------------------------------------------------------------------
-- Numeração sequencial por negócio (advisory lock)
-- -----------------------------------------------------------------------------
create or replace function public.proximo_numero_compra(p_negocio uuid, p_kind text)
returns integer
language plpgsql
set search_path = public
as $$
declare n integer;
begin
  perform pg_advisory_xact_lock(hashtext('compra_num_' || p_kind || '_' || p_negocio::text));
  if p_kind = 'req' then
    select coalesce(max(numero), 0) + 1 into n from public.compra_requisicoes where negocio_id = p_negocio;
  else
    select coalesce(max(numero), 0) + 1 into n from public.compras where negocio_id = p_negocio;
  end if;
  return n;
end;
$$;
revoke all on function public.proximo_numero_compra(uuid, text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Proteção: requisição/pedido só mudam pelo motor (colunas de decisão e status).
-- Colunas "diário" (justificativa em pendente etc.) ficam livres para edição
-- do solicitante; o motor cuida do resto.
-- -----------------------------------------------------------------------------
create or replace function public.tg_compras_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Compras: use cancelamento, não delete.' using errcode = 'check_violation';
  end if;
  if coalesce(current_setting('erp.motor', true), '') <> 'on' then
    if tg_table_name = 'compra_requisicoes' and tg_op = 'UPDATE'
       and (new.status is distinct from old.status or new.aprovador_id is distinct from old.aprovador_id
            or new.decidido_em is distinct from old.decidido_em or new.pedido_id is distinct from old.pedido_id
            or new.numero is distinct from old.numero) then
      raise exception 'Decisão da requisição só pelo motor (aprovar/rejeitar/cancelar).' using errcode = 'insufficient_privilege';
    end if;
    if tg_table_name = 'compras' and tg_op = 'UPDATE'
       and (new.status is distinct from old.status or new.numero is distinct from old.numero) then
      raise exception 'Status do pedido é do motor.' using errcode = 'insufficient_privilege';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function public.tg_compras_protecao() from public, anon, authenticated;
create trigger compra_req_protecao before update or delete on public.compra_requisicoes for each row execute function public.tg_compras_protecao();
create trigger compras_protecao before update or delete on public.compras for each row execute function public.tg_compras_protecao();

-- -----------------------------------------------------------------------------
-- Motor
-- -----------------------------------------------------------------------------
-- Criar requisição: qualquer membro. p_itens jsonb array de
--   {"descricao": text, "quantidade": num, "destino": text ('estoque'|...), "item_id"?: uuid, "observacao"?: text}
create function public.criar_requisicao_compra(
  p_negocio_id uuid, p_itens jsonb, p_justificativa text default null
)
returns public.compra_requisicoes
language plpgsql
security definer
set search_path = public
as $$
declare
  n public.negocios%rowtype; r public.compra_requisicoes%rowtype; linha jsonb; v_num integer;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(n.organizacao_id);
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Informe ao menos um item na requisição.' using errcode = 'check_violation';
  end if;
  v_num := public.proximo_numero_compra(n.id, 'req');
  perform set_config('erp.motor', 'on', true);
  insert into public.compra_requisicoes (organizacao_id, negocio_id, numero, solicitante_id, justificativa)
  values (n.organizacao_id, n.id, v_num, auth.uid(), nullif(btrim(coalesce(p_justificativa, '')), ''))
  returning * into r;
  declare v_i int := 0;
  begin
    for linha in select * from jsonb_array_elements(p_itens) loop
      insert into public.compra_requisicao_itens (requisicao_id, ordem, item_id, descricao, quantidade, destino, observacao)
      values (
        r.id, v_i,
        nullif(linha->>'item_id', '')::uuid,
        btrim(coalesce(linha->>'descricao', '')),
        (linha->>'quantidade')::numeric,
        coalesce(linha->>'destino', 'estoque')::public.destino_compra_item,
        nullif(btrim(coalesce(linha->>'observacao', '')), '')
      );
      v_i := v_i + 1;
    end loop;
  end;
  return r;
end;
$$;

-- Rejeitar requisição — só proprietário.
create function public.rejeitar_requisicao_compra(p_id uuid, p_motivo text)
returns public.compra_requisicoes
language plpgsql
security definer
set search_path = public
as $$
declare r public.compra_requisicoes%rowtype;
begin
  select * into r from public.compra_requisicoes where id = p_id;
  if not found then raise exception 'Requisição não encontrada.' using errcode = 'no_data_found'; end if;
  if not public.sou_proprietario(r.organizacao_id) then
    raise exception 'Apenas o proprietário pode aprovar/rejeitar.' using errcode = 'insufficient_privilege';
  end if;
  if r.status <> 'pendente' then raise exception 'Requisição já decidida (%).', r.status using errcode = 'check_violation'; end if;
  if coalesce(btrim(p_motivo), '') = '' then raise exception 'Informe o motivo da rejeição.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.compra_requisicoes set status = 'rejeitada', aprovador_id = auth.uid(), decidido_em = now(), motivo_rejeicao = btrim(p_motivo) where id = p_id
  returning * into r;
  return r;
end;
$$;

-- Cancelar requisição (pelo solicitante, enquanto pendente).
create function public.cancelar_requisicao_compra(p_id uuid)
returns public.compra_requisicoes
language plpgsql
security definer
set search_path = public
as $$
declare r public.compra_requisicoes%rowtype;
begin
  select * into r from public.compra_requisicoes where id = p_id;
  if not found then raise exception 'Requisição não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(r.organizacao_id);
  if r.status <> 'pendente' then raise exception 'Só é possível cancelar requisição pendente.' using errcode = 'check_violation'; end if;
  if r.solicitante_id <> auth.uid() and not public.sou_proprietario(r.organizacao_id) then
    raise exception 'Apenas o solicitante ou o proprietário podem cancelar.' using errcode = 'insufficient_privilege';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.compra_requisicoes set status = 'cancelada', decidido_em = now(), aprovador_id = auth.uid() where id = p_id
  returning * into r;
  return r;
end;
$$;

-- Aprovar requisição: cria o Pedido (compras + compra_itens) copiando os itens
-- da requisição, aplicando p_valores por item. p_valores: jsonb array na mesma
-- ORDEM dos itens da requisição, cada um com {"valor_unitario": num,
-- "categoria_id"?: uuid, "contrato_id"?: uuid}. Fornecedor/frete/desconto/
-- condição vêm nos parâmetros do pedido.
create function public.aprovar_requisicao_compra(
  p_id uuid,
  p_fornecedor_id uuid,
  p_valores jsonb,
  p_data_pedido date default current_date,
  p_previsao_entrega date default null,
  p_condicao_pagamento text default null,
  p_valor_frete numeric default 0,
  p_valor_desconto numeric default 0,
  p_observacao text default null
)
returns public.compras
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.compra_requisicoes%rowtype; c public.compras%rowtype;
  ri public.compra_requisicao_itens; v_num integer;
  v_valores jsonb; v_val jsonb; v_idx int := 0;
begin
  select * into r from public.compra_requisicoes where id = p_id;
  if not found then raise exception 'Requisição não encontrada.' using errcode = 'no_data_found'; end if;
  if not public.sou_proprietario(r.organizacao_id) then
    raise exception 'Apenas o proprietário pode aprovar.' using errcode = 'insufficient_privilege';
  end if;
  if r.status <> 'pendente' then raise exception 'Requisição já decidida (%).', r.status using errcode = 'check_violation'; end if;
  if p_valores is null or jsonb_typeof(p_valores) <> 'array' then
    raise exception 'Informe os valores por item (array na mesma ordem).' using errcode = 'check_violation';
  end if;
  v_num := public.proximo_numero_compra(r.negocio_id, 'ped');
  perform set_config('erp.motor', 'on', true);
  insert into public.compras (organizacao_id, negocio_id, requisicao_id, fornecedor_id, numero, data_pedido, previsao_entrega, condicao_pagamento, valor_frete, valor_desconto, observacao, criado_por)
  values (r.organizacao_id, r.negocio_id, r.id, p_fornecedor_id, v_num, coalesce(p_data_pedido, current_date), p_previsao_entrega, nullif(btrim(coalesce(p_condicao_pagamento, '')), ''), coalesce(p_valor_frete, 0), coalesce(p_valor_desconto, 0), nullif(btrim(coalesce(p_observacao, '')), ''), auth.uid())
  returning * into c;
  for ri in select * from public.compra_requisicao_itens where requisicao_id = r.id order by ordem loop
    v_val := p_valores -> v_idx;
    if v_val is null then raise exception 'Faltou valor para o item %.', ri.descricao using errcode = 'check_violation'; end if;
    insert into public.compra_itens (compra_id, item_id, descricao, quantidade, valor_unitario, destino, categoria_id, contrato_id, observacao)
    values (c.id, ri.item_id, ri.descricao, ri.quantidade,
            (v_val->>'valor_unitario')::numeric,
            ri.destino,
            nullif(v_val->>'categoria_id', '')::uuid,
            nullif(v_val->>'contrato_id', '')::uuid,
            ri.observacao);
    v_idx := v_idx + 1;
  end loop;
  update public.compra_requisicoes set status = 'convertida', aprovador_id = auth.uid(), decidido_em = now(), pedido_id = c.id where id = r.id;
  return c;
end;
$$;

-- Cancelar pedido — só proprietário; enquanto ainda não teve recebimento.
create function public.cancelar_pedido_compra(p_id uuid, p_motivo text default null)
returns public.compras
language plpgsql
security definer
set search_path = public
as $$
declare c public.compras%rowtype;
begin
  select * into c from public.compras where id = p_id;
  if not found then raise exception 'Pedido não encontrado.' using errcode = 'no_data_found'; end if;
  if not public.sou_proprietario(c.organizacao_id) then
    raise exception 'Apenas o proprietário pode cancelar o pedido.' using errcode = 'insufficient_privilege';
  end if;
  if c.status <> 'aberto' then raise exception 'Só é possível cancelar pedido em aberto (%).', c.status using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  update public.compras set status = 'cancelado', observacao = coalesce(observacao, '') || case when p_motivo is not null then E'\nCancelado: ' || p_motivo else '' end where id = p_id
  returning * into c;
  return c;
end;
$$;

revoke all on function
  public.criar_requisicao_compra(uuid, jsonb, text),
  public.rejeitar_requisicao_compra(uuid, text),
  public.cancelar_requisicao_compra(uuid),
  public.aprovar_requisicao_compra(uuid, uuid, jsonb, date, date, text, numeric, numeric, text),
  public.cancelar_pedido_compra(uuid, text)
from public, anon;
grant execute on function
  public.criar_requisicao_compra(uuid, jsonb, text),
  public.rejeitar_requisicao_compra(uuid, text),
  public.cancelar_requisicao_compra(uuid),
  public.aprovar_requisicao_compra(uuid, uuid, jsonb, date, date, text, numeric, numeric, text),
  public.cancelar_pedido_compra(uuid, text)
to authenticated;

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
alter table public.compra_requisicoes enable row level security;
alter table public.compra_requisicao_itens enable row level security;
alter table public.compras enable row level security;
alter table public.compra_itens enable row level security;

create policy compra_req_org on public.compra_requisicoes using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy compra_req_itens_org on public.compra_requisicao_itens using (exists (select 1 from public.compra_requisicoes r where r.id = requisicao_id and r.organizacao_id in (select public.minhas_organizacoes()))) with check (exists (select 1 from public.compra_requisicoes r where r.id = requisicao_id and r.organizacao_id in (select public.minhas_organizacoes())));
create policy compras_org on public.compras using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
create policy compra_itens_org on public.compra_itens using (exists (select 1 from public.compras c where c.id = compra_id and c.organizacao_id in (select public.minhas_organizacoes()))) with check (exists (select 1 from public.compras c where c.id = compra_id and c.organizacao_id in (select public.minhas_organizacoes())));

revoke all on public.compra_requisicoes, public.compra_requisicao_itens, public.compras, public.compra_itens from public, anon, authenticated;
grant select, insert, update on public.compra_requisicoes to authenticated;
grant select, insert on public.compra_requisicao_itens to authenticated;
grant select, insert, update on public.compras to authenticated;
grant select, insert on public.compra_itens to authenticated;

-- -----------------------------------------------------------------------------
-- Views para a Central de Relatórios (55A entrega dois relatórios)
-- -----------------------------------------------------------------------------
create view public.vw_rel_compras_requisicoes_pendentes with (security_invoker = true) as
select r.organizacao_id,
       r.id as requisicao_id,
       r.numero,
       n.nome as negocio,
       r.criado_em::date as data,
       coalesce(u_sol.raw_user_meta_data->>'nome', u_sol.email, 'Solicitante') as solicitante,
       r.justificativa,
       (select count(*) from public.compra_requisicao_itens i where i.requisicao_id = r.id) as itens,
       (select sum(quantidade) from public.compra_requisicao_itens i where i.requisicao_id = r.id) as quantidade_total
  from public.compra_requisicoes r
  join public.negocios n on n.id = r.negocio_id
  left join auth.users u_sol on u_sol.id = r.solicitante_id
 where r.status = 'pendente';
grant select on public.vw_rel_compras_requisicoes_pendentes to authenticated;

create view public.vw_rel_compras_pedidos_abertos with (security_invoker = true) as
select c.organizacao_id,
       c.id as compra_id,
       c.numero,
       c.data_pedido,
       c.previsao_entrega,
       n.nome as negocio,
       p.nome as fornecedor,
       c.status,
       t.total_final as valor,
       c.condicao_pagamento
  from public.compras c
  join public.negocios n on n.id = c.negocio_id
  left join public.pessoas p on p.id = c.fornecedor_id
  left join public.vw_compras_totais t on t.compra_id = c.id
 where c.status in ('aberto', 'recebido_parcial');
grant select on public.vw_rel_compras_pedidos_abertos to authenticated;
