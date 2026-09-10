# Etapa 28 — Estoque

Controle de estoque da Servnet (modelo por `negocio_id`, pronto para Precautec no futuro). Entregue em duas etapas; esta doc cobre a **Etapa A**.

## Banco (migration `20260902000053_estoque.sql`)

- Enums `tipo_movimentacao_estoque` (entrada/saida/ajuste) e `origem_movimentacao_estoque` (compra/instalacao/devolucao/ajuste/perda/inventario).
- `estoque_categorias`: por negócio, nome único, seed das 5 categorias padrão (Cabos, Conectores, Equipamentos, Ferramentas, Fixação) para negócios ativos. Editáveis.
- `estoque_itens`: código único por organização, unidade (unidade/metro/caixa/pacote/rolo/par — quantidades decimais), `valor_custo` = **custo médio ponderado** (numeric 12,4), quantidade mínima/máxima para alertas. Item **nasce zerado** — saldo só entra por movimentação.
- `estoque_movimentacoes`: **imutáveis** (UPDATE/DELETE sempre bloqueados); insert só pelo motor. Guardam custo unitário e total, pessoa/contrato/lançamento vinculados e usuário.
- Funções (security definer, flag `erp.motor`):
  - `entrada_estoque(item, qtd, valor_total, data, origem, lancamento_id, obs)` — recalcula o custo médio ponderado (valor da compra rateado pela quantidade).
  - `saida_estoque(item, qtd, origem instalacao|perda, data, pessoa, contrato, obs)` — baixa pelo custo médio; bloqueia acima do disponível.
  - `ajuste_estoque(item, quantidade_nova, valor_total?, obs)` — grava o delta; com valor informado redefine o custo (inventário).
- Proteções: quantidade/custo do item não editáveis direto; sem DELETE; RLS por organização.

## App (`app/src/modules/estoque/`, rota `/estoque`)

Abas com seletor de negócio (padrão Servnet):

- **Dashboard**: cartões (itens ativos, baixo/zerado, valor total do estoque = qtd × custo médio — ferramentas incluídas, consumo do mês) + alerta de itens zerados/baixos no topo.
- **Itens**: cadastro (nasce zerado), status Zerado/Baixo/Excesso/Normal.
- **Nova compra** (na aba Itens): várias linhas de itens (qtd + valor total) e **pagamento misto** — um lançamento de despesa por forma de pagamento (cartão de crédito → entra na fatura como previsto; pix/dinheiro/etc. → efetivado se marcado como pago). Soma dos pagamentos deve bater com a soma dos itens. As entradas de estoque ficam amarradas ao lançamento.
- **Movimentações**: histórico imutável; ações de ajuste de inventário, perda e devolução (devolução reentra pelo custo médio — despesa **não** é gerada de novo).
- **Categorias**: criar/renomear/desativar.

## Fica para a Etapa B

Instalações (consumo de materiais + mão de obra por cliente/contrato, vínculo com porta FTTH), payback no contrato (estimado custo÷mensalidade e real pelos recebimentos), aba de relatórios e cartão de alertas de estoque no Dashboard geral.

## Testes

`supabase/tests/estoque_test.sql`: item nasce zerado, custo médio ponderado (0,80 + 1,20 → 1,00), saída pelo custo médio, bloqueio acima do estoque, imutabilidade das movimentações, ajuste com delta, devolução e vínculo com cliente. `verificar_tudo.sql`: 41 de 41.
