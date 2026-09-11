-- =============================================================================
-- 0065 · Etapa 39 — Natureza da categoria: operacional × investimento
-- =============================================================================
-- Cada categoria de despesa pode ser marcada como "investimento" (compra de
-- ativo: móveis, equipamentos, obra). O resultado OPERACIONAL do período passa
-- a ser calculável sem os investimentos distorcerem o mês. Receita continua
-- sempre operacional (o campo existe, mas o app só expõe para despesa).
-- A herança pai→filha é feita pelo app (o formulário sugere a natureza do
-- pai), sem trigger — assim uma escolha explícita nunca é sobrescrita.
-- =============================================================================

create type public.natureza_categoria as enum ('operacional', 'investimento');

alter table public.categorias
  add column natureza public.natureza_categoria not null default 'operacional';

comment on column public.categorias.natureza is
  'operacional = custo do dia a dia; investimento = compra de ativo (não entra no resultado operacional).';
