# Etapa 28 — Estoque

Controle de estoque da Servnet (modelo por `negocio_id`, pronto para Precautec no futuro). Entregue em duas etapas; esta doc cobre as **Etapas A e B**.

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

## Etapa B — Instalações, payback e relatórios (migration `20260902000054_estoque_instalacoes.sql`)

### Banco

- `estoque_instalacoes`: registro imutável do serviço no cliente — materiais consumidos (`custo_material`, derivado das saídas), `mao_de_obra` informada, `custo_total` gerado (material + mão de obra), técnico, contrato e porta da CTO opcionais. Insert só pelo motor; UPDATE/DELETE bloqueados (o motor só regrava o custo do material).
- `estoque_movimentacoes.instalacao_id`: cada saída da instalação fica amarrada a ela.
- `registrar_instalacao(negocio, pessoa, contrato?, porta?, data, itens jsonb, mao_de_obra, tecnico?, obs?)` (security definer, flag `erp.motor`): valida cliente/contrato/porta, baixa cada item pelo custo médio (`saida_estoque` com origem `instalacao`) e, se a porta estiver livre (ou reservada para o cliente), vincula ao contrato pelo motor da Etapa 27 (`vincular_porta_cto`). Tudo ou nada: estoque insuficiente desfaz a instalação inteira. Porta exige contrato; porta ocupada por outro cliente é bloqueada. Só mão de obra (sem itens e sem porta) é permitido.
- A mão de obra é custo para o payback; se paga a terceiro, a despesa é lançada normalmente no Financeiro (não é gerada aqui).
- `saida_estoque` ganhou assinatura com `p_instalacao_id`; a antiga (7 parâmetros) delega para a nova.
- Views (`security_invoker`):
  - `vw_payback_contrato`: custo das instalações do contrato, mensalidade normalizada (bimestral/2 … anual/12; único = 0), `payback_estimado_meses` = teto(custo ÷ mensalidade), `recebido` (receitas efetivadas), `data_payback_real` (dia em que o acumulado cobriu o custo) e `payback_real_meses` (da 1ª instalação ao pagamento).
  - `vw_estoque_consumo_mensal` (negócio × mês × tipo × origem) e `vw_estoque_consumo_item` (saídas por item e mês).

### App

- Estoque ganhou o botão **Nova instalação** e as abas **Instalações** (histórico imutável: cliente, material, mão de obra, total, técnico) e **Relatórios** (consumo por mês/origem e itens mais consumidos).
- Formulário da instalação: cliente → contrato ativo (opcional) → CTO/porta (opcional; porta livre, reservada ou já do cliente), linhas de materiais com prévia do custo pelo custo médio, mão de obra, técnico. Escolher porta exige contrato.
- Contratos → detalhe: bloco **Payback da instalação** (custo, estimado em meses, recebido e "pago em"/"faltam R$").
- Dashboard geral: cartão **Estoque** com itens zerados/abaixo do mínimo (só aparece se houver alerta), respeitando o filtro de negócio.

## Testes

`supabase/tests/estoque_test.sql`: item nasce zerado, custo médio ponderado (0,80 + 1,20 → 1,00), saída pelo custo médio, bloqueio acima do estoque, imutabilidade das movimentações, ajuste com delta, devolução e vínculo com cliente.
`supabase/tests/estoque_instalacoes_test.sql`: instalação baixa itens pelo custo médio e vincula a porta ao contrato; imutabilidade; bloqueios (estoque insuficiente desfaz tudo, contrato de outro cliente, porta ocupada); payback estimado (350/100 → 4 meses) e real (data e meses); views de consumo. `verificar_tudo.sql`: 42 de 42.
