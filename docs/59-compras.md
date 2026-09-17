# Etapa 55 — Módulo Compras

> **Status: 55A entregue (17/09/2026).** Decisão revisada: fluxo formal SEMPRE
> (`exige_aprovacao` = true fixo no MVP), estilo ERP grande. Aprovador é o
> proprietário da organização — hoje só o dono. 55B (Recebimento → Nota →
> Lançamento) fica na próxima entrega.

## 1. O princípio que resolve o dilema

**A estrutura é de time grande. A tela é de uma pessoa só.**

O banco guarda a cadeia inteira — quem pediu, quem aprovou, quando, o que foi
pedido, o que chegou, o que a nota cobrou. O app decide **quantas telas** disso o
usuário atravessa, por uma configuração por negócio:

| Configuração | Hoje (1 pessoa) | Amanhã (time) |
|---|---|---|
| `exige_aprovacao` | **false** | true |
| Efeito | A compra nasce aprovada, com seu nome e horário no histórico | Requisição fica pendente até alguém aprovar |

Ligar a chave não exige migration nem retrabalho: os campos já existem e já são
preenchidos. Muda só o caminho na tela.

## 2. Fluxo completo (o que o banco sempre registra)

```
Requisição  →  Aprovação  →  Pedido  →  Recebimento  →  Nota  →  Pagamento
(o que falta)  (quem OK)   (negociado) (chegou tudo?)  (fiscal)  (lançamento)
```

Hoje, com `exige_aprovacao = false`, os três primeiros acontecem numa tela só, e a
nota entra junto do recebimento. O histórico, porém, nasce completo.

## 3. Estrutura de dados

**`compra_requisicoes`** — a necessidade, sem valor
`id, organizacao_id, negocio_id, solicitante_id (pessoa/técnico), item_id (opcional),
descricao, quantidade, justificativa, status (pendente|aprovada|rejeitada|atendida),
aprovado_por, aprovado_em, motivo_rejeicao, criado_em`

> Aproveita o que já existe: `reposicao_solicitacoes` (o técnico pedindo material pelo
> app) vira origem de requisição quando o estoque não tem o item.

**`compras`** — o pedido, coração do módulo
`id, organizacao_id, negocio_id, fornecedor_id, requisicao_id (opcional), numero,
data_pedido, previsao_entrega, valor_frete, valor_desconto, condicao_pagamento,
status (pedido|recebido_parcial|recebido|cancelado), observacao, criado_em`

> **Não** grava `valor_total` nem `valor_final` (derivados: view soma os itens + frete −
> desconto). **Não** grava "pago": isso vem dos lançamentos.

**`compra_itens`** — o que foi pedido e para onde vai
`id, compra_id, item_id (se estoque), descricao, quantidade, valor_unitario,
categoria_id, centro_custo_id, contrato_id (compra para um cliente),
destino (estoque|despesa|patrimonio|comodato|servico), quantidade_recebida`

> `destino` é o equivalente à classificação contábil do item no SAP: é ele que diz o
> que o recebimento vai disparar.

**`compra_recebimentos`** — o que chegou, com a nota
`id, compra_id, data, conferido_por, chegou_tudo (bool), nota_numero, nota_chave,
nota_valor, anexo_caminho, observacao, criado_em`

**`compra_recebimento_itens`** — quantidade por item naquele recebimento
`id, recebimento_id, compra_item_id, quantidade, numero_serie (patrimônio/comodato)`

## 4. Regra inegociável: a compra não grava nada sozinha

Compras **orquestra**, nunca escreve em `lancamentos` nem em `estoque_itens`.
Toda ação passa pelas funções que já existem e já são testadas:

| Destino do item | O recebimento chama |
|---|---|
| estoque | `entrada_estoque` |
| patrimônio | `salvar_patrimonio` |
| comodato | `registrar_comodato` (com baixa, via estoque) |
| despesa / serviço | nada no estoque |
| **sempre** | `criar_lancamento` (à vista ou N parcelas) + `definir_centro_custo_lancamento` |

Isso garante o "não duplicar lançamento": existe **um** caminho para dinheiro entrar
no financeiro, e ele continua sendo o motor.

## 5. Quando cada coisa acontece

- **Pedido salvo:** nada de estoque, nada de dinheiro. É intenção.
  Aparece em "a receber de fornecedor" — o que está a caminho.
- **Recebimento:** aí sim entra no estoque/patrimônio/comodato, **e só a quantidade
  que chegou**. Recebimento parcial é normal: o pedido fica `recebido_parcial`.
- **Lançamento financeiro:** nasce no recebimento (é quando a obrigação existe de
  fato). À vista vira 1 lançamento; parcelado, N parcelas pelo motor de recorrência.
- **Pago:** derivado. A compra nunca guarda esse status.

## 6. Three-way match adaptado — alerta, nunca trava

Na tela do recebimento, três colunas lado a lado: **pedido × recebido × nota**.

- Quantidade diferente → aviso âmbar "pedi 1.000, chegaram 998".
- Valor da nota diferente da soma dos itens → aviso âmbar com a diferença.
- Nenhum dos dois impede salvar. Quem decide é você; o sistema só não deixa passar
  despercebido.

## 7. Ordem de implementação

### 55A — entregue (0092)

- Tabelas `compra_requisicoes`, `compra_requisicao_itens`, `compras`, `compra_itens` com RLS e proteção de motor (status/decisão gravados só pelas funções).
- Motor security definer: `criar_requisicao_compra`, `aprovar_requisicao_compra` (gera o pedido), `rejeitar_requisicao_compra`, `cancelar_requisicao_compra`, `cancelar_pedido_compra`. Aprovação restrita ao proprietário (`sou_proprietario`).
- Numeração sequencial por negócio via advisory-lock (REQ-0001, PED-0001).
- View `vw_compras_totais` (soma itens + frete − desconto).
- Módulo `/compras` com abas Requisições e Pedidos, modal de decisão que pede valor unitário/categoria por item, fornecedor, condição e frete/desconto na aprovação.
- Central de Relatórios: `vw_rel_compras_requisicoes_pendentes` e `vw_rel_compras_pedidos_abertos`.
- Testes SQL: `supabase/tests/compras_requisicoes_test.sql` (7 cenários; 75/75 no `verificar_tudo.sql`).

### 55B — entregue (0093)

- Tabelas `compra_recebimentos` e `compra_recebimento_itens`, imutáveis (só INSERT pelo motor; DELETE bloqueado sempre).
- Motor `registrar_recebimento_compra(compra_id, itens jsonb, data, nota_numero, nota_chave, nota_valor, observacao, conta_id, pago, parcelas, categoria_padrao_id)`:
  - Valida que a quantidade recebida ≤ pedida − já recebida (recebimento parcial permitido).
  - Cria um lançamento de despesa (à vista ou N parcelas mensais pelo motor de recorrência), com valor = soma dos itens recebidos + frete/desconto rateados pela proporção do que chegou. Cartão de crédito → previsto; demais contas → efetivado se marcado como pago.
  - Para cada item `destino='estoque'` com `item_id`, chama `entrada_estoque` (motor de estoque) com origem `compra` e amarra ao mesmo `lancamento_id`.
  - Atualiza `compras.status` para `recebido_parcial` ou `recebido` conforme o total.
- View `vw_rel_compras_recebimentos` com marca `confere` / `divergente` / `sem nota`.
- App: modal **Registrar recebimento** no detalhe do pedido (linha por item com Pedido / Já recebido / Chega agora, nota opcional, conta e pagamento). Nova aba **Recebimentos** com histórico. Alerta âmbar quando o valor da nota diverge.
- Testes: `supabase/tests/compras_recebimento_test.sql` (parcial + total, excedente falha, imutabilidade); 76/76 no `verificar_tudo.sql`.

### 55C — entregue (0094)

- `registrar_recebimento_compra` reescrita: item destino **patrimonio** cria uma linha em `patrimonios` por unidade recebida (nome herdado do item, valor = valor unitário do pedido, localização = negócio + PED-NNNN, número de série vai para o primeiro exemplar). Comodato e Estoque seguem por `entrada_estoque` (comodato só vira comodato quando alocado a um cliente pelo módulo Estoque). Despesa/Serviço continuam só no lançamento financeiro.
- App: **Nova compra** do Estoque removida; o botão vira atalho **"Nova compra (via requisição)"** apontando para `/compras`. O alerta *Comprar* do Dashboard redireciona para o mesmo lugar. Não há caminho paralelo: toda compra passa pelo fluxo formal.
- Testes: `supabase/tests/compras_patrimonio_test.sql`; 77/77 no `verificar_tudo.sql`.

### 55D+ — pendências

- Anexo da nota fiscal (PDF/XML) — depende de autorização para Supabase Storage.
- Requisição automática a partir do alerta de estoque baixo e das solicitações do técnico.

## 8. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| O dono para de registrar por causa do fluxo longo | Tela única enquanto `exige_aprovacao = false`; o caminho de hoje não fica mais lento que a Nova compra atual |
| Dois caminhos para comprar material | Passo 3: a Nova compra do Estoque vira atalho do mesmo documento |
| Lançamento duplicado (compra + lançamento manual) | Lançamento gerado pelo recebimento fica marcado com `compra_id`; a tela avisa se já existe |
| Recebimento sem nota (chega antes) | Nota é opcional no recebimento; o alerta de divergência só liga quando ela é informada |
| Estorno de compra recebida | Cancelamento de compra recebida não apaga nada: estorna o lançamento e devolve ao estoque por movimentação nova, tudo auditado |

## 9. O que ficou de fora de propósito

- **Cotação com vários fornecedores** e mapa comparativo: só vale com volume de compra.
- **Aprovação por alçada** (até R$ X aprova sozinho): a estrutura comporta, a tela não
  precisa hoje.
- **Contrato de fornecimento / compra programada**: já existe como contrato de fornecedor.
- **Dashboard próprio**: vira relatório na Central, não tela nova.
