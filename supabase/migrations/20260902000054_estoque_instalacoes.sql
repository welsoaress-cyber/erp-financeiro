-- =============================================================================
-- 0054 · Etapa 28B — Instalações, payback do contrato e relatórios de estoque
-- =============================================================================
-- Uma INSTALAÇÃO é o registro do serviço feito no cliente: os materiais
-- consumidos (saídas de estoque pelo custo médio, origem 'instalacao') e a
-- mão de obra informada. Custo total = material + mão de obra. Fica amarrada
-- ao cliente, opcionalmente ao contrato e à porta da CTO (FTTH): se a porta
-- estiver livre (ou reservada para o cliente), ela é vinculada ao contrato na
-- hora, pelo mesmo motor de vinculação da Etapa 27.
-- Gravação só pelo motor (registrar_instalacao). Instalação é imutável.
-- A mão de obra é custo informado para o payback; se for paga a um terceiro,
-- a despesa é lançada normalmente no financeiro (não é gerada aqui).
-- Payback do contrato (view): custo das instalações ÷ mensalidade (estimado)
-- e data em que as receitas efetivadas do contrato cobriram o custo (real).
-- =============================================================================

create table public.estoque_instalacoes (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  pessoa_id uuid not null references public.pessoas (id),
  contrato_id uuid references public.contratos (id),
  porta_id uuid references public.cto_portas (id),
  data date not null default current_date,
  custo_material numeric(12,2) not null default 0 check (custo_material >= 0),
  mao_de_obra numeric(12,2) not null default 0 check (mao_de_obra >= 0),
  custo_total numeric(12,2) generated always as (custo_material + mao_de_obra) stored,
  tecnico text check (tecnico is null or char_length(tecnico) <= 80),
  observacao text check (observacao is null or char_length(observacao) <= 300),
  usuario_id uuid,
  criado_em timestamptz not null default now()
);
create index estoque_instalacoes_contrato on public.estoque_instalacoes (contrato_id) where contrato_id is not null;
create index estoque_instalacoes_pessoa on public.estoque_instalacoes (pessoa_id);
create index estoque_instalacoes_negocio_data on public.estoque_instalacoes (negocio_id, data desc);

alter table public.estoque_movimentacoes add column instalacao_id uuid references public.estoque_instalacoes (id);
create index estoque_mov_instalacao on public.estoque_movimentacoes (instalacao_id) where instalacao_id is not null;

-- instalação: só pelo motor; nunca some; só o custo do material (derivado) muda, e só pelo motor
create or replace function public.tg_estoque_instalacoes_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Instalação é imutável: corrija com uma nova instalação ou ajuste de estoque.' using errcode = 'check_violation';
  end if;
  if coalesce(current_setting('erp.motor', true), '') <> 'on' then
    raise exception 'Instalações são gravadas pelo motor (registrar_instalacao).' using errcode = 'insufficient_privilege';
  end if;
  if tg_op = 'UPDATE' and row(new.organizacao_id, new.negocio_id, new.pessoa_id, new.contrato_id, new.porta_id, new.data, new.mao_de_obra, new.tecnico, new.observacao, new.usuario_id, new.criado_em)
     is distinct from row(old.organizacao_id, old.negocio_id, old.pessoa_id, old.contrato_id, old.porta_id, old.data, old.mao_de_obra, old.tecnico, old.observacao, old.usuario_id, old.criado_em) then
    raise exception 'Instalação é imutável: corrija com uma nova instalação ou ajuste de estoque.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.tg_estoque_instalacoes_protecao() from public, anon, authenticated;
create trigger estoque_instalacoes_protecao before insert or update or delete on public.estoque_instalacoes for each row execute function public.tg_estoque_instalacoes_protecao();

-- saída de estoque ganha o vínculo com a instalação (assinatura nova com p_instalacao_id; a antiga delega)
create function public.saida_estoque(
  p_item_id uuid, p_quantidade numeric, p_origem text, p_data date,
  p_pessoa_id uuid, p_contrato_id uuid, p_observacao text, p_instalacao_id uuid
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
    raise exception 'Saída de % maior que o estoque disponível (% %).', it.nome, it.quantidade_atual, it.unidade_medida using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.estoque_itens set quantidade_atual = quantidade_atual - p_quantidade where id = p_item_id;
  insert into public.estoque_movimentacoes (organizacao_id, negocio_id, item_id, tipo, origem, quantidade, valor_unitario, valor_total, data, pessoa_id, contrato_id, instalacao_id, observacao, usuario_id)
  values (it.organizacao_id, it.negocio_id, p_item_id, 'saida', p_origem::public.origem_movimentacao_estoque, p_quantidade, it.valor_custo, round(p_quantidade * it.valor_custo, 2), coalesce(p_data, current_date), p_pessoa_id, p_contrato_id, p_instalacao_id, p_observacao, auth.uid())
  returning * into m;
  return m;
end;
$$;
create or replace function public.saida_estoque(
  p_item_id uuid, p_quantidade numeric, p_origem text default 'perda', p_data date default current_date,
  p_pessoa_id uuid default null, p_contrato_id uuid default null, p_observacao text default null
)
returns public.estoque_movimentacoes
language sql
security definer
set search_path = public
as $$
  select public.saida_estoque(p_item_id, p_quantidade, p_origem, p_data, p_pessoa_id, p_contrato_id, p_observacao, null::uuid);
$$;
revoke all on function public.saida_estoque(uuid, numeric, text, date, uuid, uuid, text, uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Motor: registrar_instalacao
-- p_itens: jsonb [{"item_id": uuid, "quantidade": numeric}, ...] (pode ser vazio)
-- -----------------------------------------------------------------------------
create function public.registrar_instalacao(
  p_negocio_id uuid, p_pessoa_id uuid, p_contrato_id uuid, p_porta_id uuid,
  p_data date, p_itens jsonb, p_mao_de_obra numeric default 0,
  p_tecnico text default null, p_observacao text default null
)
returns public.estoque_instalacoes
language plpgsql
security definer
set search_path = public
as $$
declare
  n public.negocios%rowtype; pe public.pessoas%rowtype; ct public.contratos%rowtype; pt public.cto_portas%rowtype;
  ins public.estoque_instalacoes%rowtype; it public.estoque_itens%rowtype; m public.estoque_movimentacoes%rowtype;
  linha jsonb; v_item uuid; v_qtd numeric; v_material numeric := 0;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(n.organizacao_id);
  select * into pe from public.pessoas where id = p_pessoa_id;
  if not found or pe.organizacao_id <> n.organizacao_id then raise exception 'Cliente inválido.' using errcode = 'check_violation'; end if;
  if p_contrato_id is not null then
    select * into ct from public.contratos where id = p_contrato_id;
    if not found or ct.pessoa_id <> p_pessoa_id or ct.negocio_id <> p_negocio_id then
      raise exception 'Contrato inválido: precisa ser do cliente e do negócio da instalação.' using errcode = 'check_violation';
    end if;
  end if;
  if p_mao_de_obra is null or p_mao_de_obra < 0 then raise exception 'Mão de obra inválida.' using errcode = 'check_violation'; end if;
  if p_itens is not null and jsonb_typeof(p_itens) <> 'array' then raise exception 'Itens da instalação devem ser uma lista.' using errcode = 'check_violation'; end if;
  if p_porta_id is not null then
    select * into pt from public.cto_portas where id = p_porta_id;
    if not found or pt.organizacao_id <> n.organizacao_id then raise exception 'Porta inválida.' using errcode = 'check_violation'; end if;
    if pt.status = 'ocupada' and pt.pessoa_id <> p_pessoa_id then
      raise exception 'Porta % já está ocupada por outro cliente.', pt.numero using errcode = 'check_violation';
    end if;
    if pt.status <> 'ocupada' and p_contrato_id is null then
      raise exception 'Para vincular a porta da CTO informe o contrato ativo do cliente.' using errcode = 'check_violation';
    end if;
  end if;

  perform set_config('erp.motor', 'on', true);
  insert into public.estoque_instalacoes (organizacao_id, negocio_id, pessoa_id, contrato_id, porta_id, data, mao_de_obra, tecnico, observacao, usuario_id)
  values (n.organizacao_id, p_negocio_id, p_pessoa_id, p_contrato_id, p_porta_id, coalesce(p_data, current_date), round(p_mao_de_obra, 2), nullif(btrim(p_tecnico), ''), p_observacao, auth.uid())
  returning * into ins;

  for linha in select * from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) loop
    v_item := (linha->>'item_id')::uuid;
    v_qtd := (linha->>'quantidade')::numeric;
    select * into it from public.estoque_itens where id = v_item;
    if not found or it.negocio_id <> p_negocio_id then raise exception 'Item de estoque inválido para este negócio.' using errcode = 'check_violation'; end if;
    m := public.saida_estoque(v_item, v_qtd, 'instalacao', ins.data, p_pessoa_id, p_contrato_id, coalesce(p_observacao, 'Instalação'), ins.id);
    v_material := v_material + m.valor_total;
  end loop;
  -- custo_material é derivado das saídas; gravado pelo motor após as baixas
  update public.estoque_instalacoes set custo_material = round(v_material, 2) where id = ins.id returning * into ins;

  if p_porta_id is not null and pt.status <> 'ocupada' then
    perform public.vincular_porta_cto(p_porta_id, p_pessoa_id, p_contrato_id, false, coalesce(p_observacao, 'Instalação'));
  end if;
  return ins;
end;
$$;
revoke all on function public.registrar_instalacao(uuid, uuid, uuid, uuid, date, jsonb, numeric, text, text) from public, anon;
grant execute on function public.registrar_instalacao(uuid, uuid, uuid, uuid, date, jsonb, numeric, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Views
-- -----------------------------------------------------------------------------
-- Payback por contrato: custo das instalações vs. mensalidade e receitas efetivadas.
-- mensalidade = valor do contrato normalizado ao mês (bimestral/2 … anual/12; único = 0).
-- payback_estimado_meses = custo ÷ mensalidade (nulo sem mensalidade ou sem custo).
-- data_payback_real = data da receita efetivada em que o acumulado cobriu o custo.
create view public.vw_payback_contrato
with (security_invoker = true) as
with custo as (
  select contrato_id, sum(custo_total) as custo_instalacao, count(*) as instalacoes, min(data) as primeira_instalacao
    from public.estoque_instalacoes where contrato_id is not null group by contrato_id
), rec as (
  select l.contrato_id, l.data_efetivacao, l.valor,
         sum(l.valor) over (partition by l.contrato_id order by l.data_efetivacao, l.criado_em rows unbounded preceding) as acumulado
    from public.lancamentos l where l.tipo = 'receita' and l.status = 'efetivado' and l.contrato_id is not null
), pago as (
  select r.contrato_id, min(r.data_efetivacao) as data_payback_real
    from rec r join custo c on c.contrato_id = r.contrato_id
   where r.acumulado >= c.custo_instalacao group by r.contrato_id
), total as (
  select contrato_id, sum(valor) as recebido from rec group by contrato_id
)
select c.id as contrato_id, c.organizacao_id, c.negocio_id, c.pessoa_id, c.status, c.valor, c.periodicidade, c.data_inicio,
       coalesce(cu.custo_instalacao, 0)::numeric(12,2) as custo_instalacao,
       coalesce(cu.instalacoes, 0) as instalacoes,
       cu.primeira_instalacao,
       (case c.periodicidade when 'mensal' then c.valor when 'bimestral' then c.valor / 2 when 'trimestral' then c.valor / 3
                             when 'semestral' then c.valor / 6 when 'anual' then c.valor / 12 else 0 end)::numeric(12,2) as mensalidade,
       case when cu.custo_instalacao > 0 and c.periodicidade <> 'unico' and c.valor > 0
            then ceil(cu.custo_instalacao / (case c.periodicidade when 'mensal' then c.valor when 'bimestral' then c.valor / 2 when 'trimestral' then c.valor / 3 when 'semestral' then c.valor / 6 else c.valor / 12 end))::int
            else null end as payback_estimado_meses,
       coalesce(t.recebido, 0)::numeric(12,2) as recebido,
       p.data_payback_real,
       case when cu.custo_instalacao > 0 and p.data_payback_real is not null
            then (extract(year from age(p.data_payback_real, coalesce(cu.primeira_instalacao, c.data_inicio))) * 12
                + extract(month from age(p.data_payback_real, coalesce(cu.primeira_instalacao, c.data_inicio))))::int
            else null end as payback_real_meses
  from public.contratos c
  left join custo cu on cu.contrato_id = c.id
  left join total t on t.contrato_id = c.id
  left join pago p on p.contrato_id = c.id;

-- Consumo mensal de estoque por negócio, tipo e origem (relatórios).
create view public.vw_estoque_consumo_mensal
with (security_invoker = true) as
select m.organizacao_id, m.negocio_id, to_char(m.data, 'YYYY-MM') as mes, m.tipo, m.origem,
       count(*) as movimentacoes, sum(m.quantidade)::numeric(12,2) as quantidade, sum(m.valor_total)::numeric(12,2) as valor_total
  from public.estoque_movimentacoes m
 group by m.organizacao_id, m.negocio_id, to_char(m.data, 'YYYY-MM'), m.tipo, m.origem;

-- Consumo por item e mês (relatórios): só saídas.
create view public.vw_estoque_consumo_item
with (security_invoker = true) as
select m.organizacao_id, m.negocio_id, m.item_id, to_char(m.data, 'YYYY-MM') as mes,
       sum(m.quantidade)::numeric(12,2) as quantidade, sum(m.valor_total)::numeric(12,2) as valor_total, count(*) as movimentacoes
  from public.estoque_movimentacoes m
 where m.tipo = 'saida'
 group by m.organizacao_id, m.negocio_id, m.item_id, to_char(m.data, 'YYYY-MM');

-- -----------------------------------------------------------------------------
-- RLS e permissões
-- -----------------------------------------------------------------------------
alter table public.estoque_instalacoes enable row level security;
create policy estoque_instalacoes_org on public.estoque_instalacoes using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.estoque_instalacoes from public, anon, authenticated;
grant select on public.estoque_instalacoes to authenticated;
revoke all on public.vw_payback_contrato, public.vw_estoque_consumo_mensal, public.vw_estoque_consumo_item from public, anon;
grant select on public.vw_payback_contrato, public.vw_estoque_consumo_mensal, public.vw_estoque_consumo_item to authenticated;
