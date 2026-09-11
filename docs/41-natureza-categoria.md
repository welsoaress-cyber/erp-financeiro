# Etapa 39 — Natureza da categoria: operacional × investimento

## Contexto (centro de custo)
O "centro de custo" do sistema é o **negócio** (ex.: criar um negócio
"Administrativo" para despesas gerais) — sem módulo novo. Subcategorias
("Mobiliário" filha de "Escritório") já existiam desde a 0004, com criação
rápida também dentro do formulário de lançamento. O que faltava era
distinguir **despesa operacional** de **compra de ativo**.

## O que entrega
- **Migration `20260902000065_natureza_categoria.sql`**: enum
  `natureza_categoria` (`operacional` | `investimento`) e coluna
  `categorias.natureza` (default operacional). Sem trigger de herança: o
  formulário sugere a natureza do pai, escolha explícita vale.
- **App**:
  - Categorias: seletor "Natureza" (Despesa operacional × Investimento /
    ativo) no formulário — só para despesa; receita é sempre operacional.
  - Subcategoria criada no form (Categorias ou lançamento rápido) herda a
    natureza do pai como sugestão.
  - Dashboard → Resumo financeiro: quando há investimento no mês, aparecem
    as linhas "das quais investimentos (ativos)" e **"Resultado operacional
    (sem investimentos)"**.

## Testes
`supabase/tests/natureza_categoria_test.sql` (padrão, marcação, filha pode
divergir do pai, enum barra valor inválido). `verificar_tudo.sql`: 53.
