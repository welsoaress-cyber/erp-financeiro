-- =============================================================================
-- 0085 · DEVOLUÇÃO AO FORNECEDOR (RMA) — item 37 do levantamento
-- =============================================================================
-- "Comprei e veio com defeito; fornecedor não devolve na hora." A devolução é
-- uma PENDÊNCIA: a unidade sai do estoque (origem devolucao_fornecedor, custo
-- médio) e nasce uma RECEITA PREVISTA do reembolso no Contas a Receber
-- (conciliável). Desfechos: reembolso (efetiva a receita), troca (entrada pelo
-- MESMO custo — média preservada — e cancela a receita) ou negada (cancela a
-- receita; a saída já feita documenta a perda). Histórico imutável.
-- =============================================================================
alter type public.origem_movimentacao_estoque add value if not exists 'devolucao_fornecedor';

create type public.status_devolucao_fornecedor as enum ('aberta', 'reembolsada', 'trocada', 'negada');

create table public.devolucoes_fornecedor (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  item_id uuid not null references public.estoque_itens (id),
  movimentacao_id uuid not null references public.estoque_movimentacoes (id),
  lancamento_id uuid not null references public.lancamentos (id),
  pessoa_id uuid references public.pessoas (id),
  quantidade numeric(12,2) not null check (quantidade > 0),
  valor numeric(12,2) not null check (valor >= 0),
  motivo text not null check (char_length(btrim(motivo)) >= 3),
  status public.status_devolucao_fornecedor not null default 'aberta',
  data_envio date not null default current_date,
  data_resolucao date,
  observacao_resolucao text,
  usuario_id uuid,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index devolucoes_fornecedor_abertas on public.devolucoes_fornecedor (organizacao_id) where status = 'aberta';
alter table public.devolucoes_fornecedor enable row level security;
create policy devolucoes_fornecedor_org on public.devolucoes_fornecedor
  using (organizacao_id in (select public.minhas_organizacoes()))
  with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.devolucoes_fornecedor from public, anon, authenticated;
grant select on public.devolucoes_fornecedor to authenticated;

create function public.tg_devolucao_fornecedor_protecao()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Devolução ao fornecedor não é excluída: resolva (reembolso, troca ou negada).' using errcode = 'check_violation';
  end if;
  if coalesce(current_setting('erp.motor', true), '') <> 'on' then
    raise exception 'Devolução é gravada pelo motor (abrir/resolver devolução ao fornecedor).' using errcode = 'insufficient_privilege';
  end if;
  if tg_op = 'UPDATE' then new.atualizado_em := now(); end if;
  return new;
end $$;
create trigger devolucoes_fornecedor_protecao before insert or update or delete on public.devolucoes_fornecedor
  for each row execute function public.tg_devolucao_fornecedor_protecao();

-- Abre a devolução: saída do estoque pelo custo médio + receita prevista do reembolso.
create function public.abrir_devolucao_fornecedor(
  p_item_id uuid, p_quantidade numeric, p_motivo text, p_conta_id uuid, p_categoria_id uuid,
  p_data date default current_date, p_pessoa_id uuid default null
)
returns public.devolucoes_fornecedor
language plpgsql
security definer
set search_path = public
as $$
declare it public.estoque_itens%rowtype; m public.estoque_movimentacoes%rowtype;
        l public.lancamentos%rowtype; d public.devolucoes_fornecedor%rowtype; v_valor numeric;
begin
  select * into it from public.estoque_itens where id = p_item_id;
  if not found then raise exception 'Item não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(it.organizacao_id);
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade da devolução deve ser maior que zero.' using errcode = 'check_violation'; end if;
  if p_quantidade > it.quantidade_atual then
    raise exception 'Devolução maior que o estoque disponível (% %).', it.quantidade_atual, it.unidade_medida using errcode = 'check_violation';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Informe o motivo da devolução.' using errcode = 'check_violation'; end if;
  v_valor := round(p_quantidade * it.valor_custo, 2);

  perform set_config('erp.motor', 'on', true);
  update public.estoque_itens set quantidade_atual = quantidade_atual - p_quantidade where id = p_item_id;
  insert into public.estoque_movimentacoes (organizacao_id, negocio_id, item_id, tipo, origem, quantidade, valor_unitario, valor_total, data, pessoa_id, observacao, usuario_id)
  values (it.organizacao_id, it.negocio_id, p_item_id, 'saida', 'devolucao_fornecedor', p_quantidade, it.valor_custo, v_valor, p_data, p_pessoa_id, p_motivo, auth.uid())
  returning * into m;

  l := public.criar_lancamento(
    'receita', 'Reembolso devolução · ' || it.nome, v_valor, p_data,
    p_data + 30, null, p_conta_id, null, p_categoria_id,
    'Devolução ao fornecedor: ' || p_motivo, it.negocio_id, p_pessoa_id, null,
    false, null, null, null, 1
  );

  perform set_config('erp.motor', 'on', true);
  insert into public.devolucoes_fornecedor (organizacao_id, negocio_id, item_id, movimentacao_id, lancamento_id, pessoa_id, quantidade, valor, motivo, data_envio, usuario_id)
  values (it.organizacao_id, it.negocio_id, p_item_id, m.id, l.id, p_pessoa_id, p_quantidade, v_valor, btrim(p_motivo), p_data, auth.uid())
  returning * into d;
  return d;
end;
$$;

-- Resolve a devolução aberta: 'reembolso' | 'troca' | 'negada'.
create function public.resolver_devolucao_fornecedor(
  p_id uuid, p_desfecho text, p_data date default current_date, p_observacao text default null
)
returns public.devolucoes_fornecedor
language plpgsql
security definer
set search_path = public
as $$
declare d public.devolucoes_fornecedor%rowtype;
begin
  select * into d from public.devolucoes_fornecedor where id = p_id;
  if not found then raise exception 'Devolução não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(d.organizacao_id);
  if d.status <> 'aberta' then raise exception 'Devolução já resolvida (%).', d.status using errcode = 'check_violation'; end if;
  if p_desfecho not in ('reembolso', 'troca', 'negada') then raise exception 'Desfecho inválido (reembolso, troca ou negada).' using errcode = 'check_violation'; end if;

  if p_desfecho = 'reembolso' then
    perform public.efetivar_lancamento(d.lancamento_id, p_data, 0, null);
  elsif p_desfecho = 'troca' then
    -- entra pelo MESMO valor que saiu: custo médio preservado, sem custo novo
    perform public.entrada_estoque(d.item_id, d.quantidade, d.valor, p_data, 'devolucao', null,
      'Troca na devolução ao fornecedor' || coalesce(': ' || p_observacao, ''));
    perform public.cancelar_lancamento(d.lancamento_id, 'Devolução resolvida como troca');
  else
    perform public.cancelar_lancamento(d.lancamento_id, 'Devolução negada pelo fornecedor');
  end if;

  perform set_config('erp.motor', 'on', true);
  update public.devolucoes_fornecedor
     set status = case p_desfecho when 'reembolso' then 'reembolsada' when 'troca' then 'trocada' else 'negada' end::public.status_devolucao_fornecedor,
         data_resolucao = p_data, observacao_resolucao = p_observacao
   where id = p_id
  returning * into d;
  return d;
end;
$$;

revoke all on function public.abrir_devolucao_fornecedor(uuid, numeric, text, uuid, uuid, date, uuid),
  public.resolver_devolucao_fornecedor(uuid, text, date, text) from public, anon;
grant execute on function public.abrir_devolucao_fornecedor(uuid, numeric, text, uuid, uuid, date, uuid),
  public.resolver_devolucao_fornecedor(uuid, text, date, text) to authenticated;

-- Relatório junto com o dado (Central de Relatórios)
create view public.vw_rel_devolucoes_fornecedor
with (security_invoker = true) as
select d.organizacao_id, d.negocio_id, coalesce(n.nome, '—') as negocio,
       d.id as devolucao_id, i.id as item_id, i.nome as item, i.codigo,
       d.quantidade, d.valor, d.motivo, d.status::text as situacao,
       d.data_envio, d.data_resolucao, d.observacao_resolucao,
       p.nome as fornecedor,
       l.status::text as situacao_reembolso
  from public.devolucoes_fornecedor d
  join public.estoque_itens i on i.id = d.item_id
  join public.lancamentos l on l.id = d.lancamento_id
  left join public.pessoas p on p.id = d.pessoa_id
  left join public.negocios n on n.id = d.negocio_id;
grant select on public.vw_rel_devolucoes_fornecedor to authenticated;
