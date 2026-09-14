-- =============================================================================
-- 0079 · CENTRAL DE RELATÓRIOS — 53A (Etapa 53)
-- =============================================================================
-- Arquitetura: uma VIEW versionada por relatório (security_invoker → RLS de
-- lancamentos vale), catálogo em código no app, tela genérica. Nada de SQL
-- dinâmico nem query gravada em tabela. Única tabela: favoritos por usuário.
--
-- 1) Centro de custo = negócio (etapa 39). Faltava enxergar todos lado a lado:
-- receita, despesa operacional, investimento e resultado do mês por negócio,
-- com detalhe por categoria. View derivada (nada gravado), security_invoker
-- (RLS de lancamentos vale), granularidade categoria × status para o app somar.
-- negocio_id nulo = pessoal. Cancelados não entram; estornos entram negativos.
-- =============================================================================
create view public.vw_centro_custo_mensal
with (security_invoker = true) as
select l.organizacao_id,
       l.negocio_id,
       date_trunc('month', l.data_competencia)::date as mes,
       l.tipo,
       l.status,
       l.categoria_id,
       coalesce(c.nome, '(sem categoria)') as categoria,
       coalesce(c.natureza, 'operacional'::public.natureza_categoria) as natureza,
       sum(l.valor)::numeric(14,2) as valor,
       count(*)::int as lancamentos
  from public.lancamentos l
  left join public.categorias c on c.id = l.categoria_id
 where l.status in ('previsto', 'efetivado') and l.tipo in ('receita', 'despesa')
 group by l.organizacao_id, l.negocio_id, date_trunc('month', l.data_competencia), l.tipo, l.status, l.categoria_id, c.nome, c.natureza;
grant select on public.vw_centro_custo_mensal to authenticated;

-- 2) Lançamentos com os nomes resolvidos (listagem, contas a receber/pagar previsto × realizado)
create view public.vw_rel_lancamentos
with (security_invoker = true) as
select l.id, l.organizacao_id, l.tipo, l.status, l.descricao, l.valor,
       l.data_competencia, l.data_vencimento, l.data_efetivacao, l.origem,
       l.conta_id, ct.nome as conta,
       l.categoria_id, c.nome as categoria, coalesce(c.natureza, 'operacional'::public.natureza_categoria) as natureza,
       l.negocio_id, coalesce(n.nome, 'Pessoal') as negocio,
       l.pessoa_id, p.nome as pessoa,
       l.contrato_id, k.codigo as contrato_codigo
  from public.lancamentos l
  left join public.contas ct on ct.id = l.conta_id
  left join public.categorias c on c.id = l.categoria_id
  left join public.negocios n on n.id = l.negocio_id
  left join public.pessoas p on p.id = l.pessoa_id
  left join public.contratos k on k.id = l.contrato_id
 where l.tipo in ('receita', 'despesa');
grant select on public.vw_rel_lancamentos to authenticated;

-- 3) Inadimplência: receitas previstas já vencidas, com dias de atraso
create view public.vw_rel_inadimplencia
with (security_invoker = true) as
select l.id, l.organizacao_id, l.negocio_id, coalesce(n.nome, 'Pessoal') as negocio,
       l.pessoa_id, p.nome as pessoa, p.telefone,
       l.contrato_id, k.codigo as contrato_codigo,
       l.descricao, l.valor, l.data_vencimento,
       (current_date - l.data_vencimento)::int as dias_atraso
  from public.lancamentos l
  left join public.negocios n on n.id = l.negocio_id
  left join public.pessoas p on p.id = l.pessoa_id
  left join public.contratos k on k.id = l.contrato_id
 where l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date;
grant select on public.vw_rel_inadimplencia to authenticated;

-- 4) Favoritos: filtros salvos por usuário (relatorio = id do catálogo no app)
create table public.relatorios_favoritos (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  usuario_id uuid not null default auth.uid(),
  relatorio text not null check (char_length(relatorio) between 1 and 60),
  nome text not null check (char_length(btrim(nome)) between 1 and 80),
  filtros jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);
alter table public.relatorios_favoritos enable row level security;
create policy favoritos_select on public.relatorios_favoritos for select to authenticated
  using (usuario_id = auth.uid() and organizacao_id in (select public.minhas_organizacoes()));
create policy favoritos_insert on public.relatorios_favoritos for insert to authenticated
  with check (usuario_id = auth.uid() and organizacao_id in (select public.minhas_organizacoes()));
create policy favoritos_update on public.relatorios_favoritos for update to authenticated
  using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());
revoke all on public.relatorios_favoritos from anon;
grant select, insert, update on public.relatorios_favoritos to authenticated;

-- remover favorito: sem grant de DELETE na tabela (regra do projeto); função só apaga o próprio
create function public.remover_relatorio_favorito(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.relatorios_favoritos where id = p_id and usuario_id = auth.uid();
  if not found then raise exception 'Favorito não encontrado.' using errcode = 'no_data_found'; end if;
end;
$$;
revoke all on function public.remover_relatorio_favorito(uuid) from public, anon;
grant execute on function public.remover_relatorio_favorito(uuid) to authenticated;
