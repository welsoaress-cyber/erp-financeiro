# Etapa 64 — Compras: modelo conceitual por papel (departamentos)

> **Status: documento para revisão. Nada implementado ainda sob este modelo.**
> Existe código de uma tentativa anterior (migration 0114 + app), feito de forma
> reativa antes deste documento — está no disco, **não commitado, não enviado**.
> Só volta a ser usado se este modelo for aprovado e ele continuar batendo com
> ele; senão é descartado sem custo.

## 0. Por que este documento existe

A conversa dos últimos pedidos foi reativa: você apontava um problema
("cartão cobrado mas ERP não sabe", "aprovador não deveria escolher
parcela"), eu corrigia só aquele ponto, e o próximo problema aparecia porque o
modelo debaixo nunca foi desenhado por inteiro. Resultado: nomes que não
dizem quem faz o quê, e status que mistura duas perguntas diferentes
("já paguei?" e "já chegou?") numa coisa só.

Este documento fecha o modelo inteiro de uma vez — documentos, papéis,
status, e quem vê o quê — antes de tocar em código de novo.

## 1. Documentos

Cada documento é uma pergunta diferente. Um pedido passa pelos quatro, em
qualquer ordem entre Pagamento e Recebimento (pagar antes de chegar, ou pagar
só quando chegar — os dois são normais).

| Documento | Pergunta que responde | Quem escreve | Tabela |
|---|---|---|---|
| **Requisição** | "Do que eu preciso?" | Solicitante | `compra_requisicoes` (existe) |
| **Pedido** | "O que foi negociado, com quem, por quanto?" | Compras | `compras` + `compra_itens` (existe) |
| **Pagamento** | "Quando e como isso foi/será pago?" | Financeiro | não é tabela nova — é o `lancamento_id` do pedido apontando pro motor financeiro (`lancamentos`), reaproveitando o que já existe. Documento conceitual, não fisicamente novo. |
| **Recebimento** | "O que chegou de verdade, e quando?" | Suprimentos | `compra_recebimentos` + `compra_recebimento_itens` (existe) |

Isso já está com os dados certos hoje; o que falta é a tela e o nome
tratarem os quatro como coisas separadas, em vez de dois (Aprovação faz
Pedido+preço junto; Recebimento faz Recebimento+Pagamento junto).

## 2. Papéis

Resumo de uma linha por papel — a referência a voltar sempre que um nome de
ação ou tela gerar dúvida:

| Papel | Responsabilidade |
|---|---|
| **Solicitante** | Pede |
| **Compras** | Negocia, cota, faz pedido |
| **Aprovador** | Aprova ou rejeita |
| **Financeiro** | Paga |
| **Suprimentos** | Recebe e confere |

Detalhando cada um (o que decide vs. o que não decide):

| Papel | O que decide | O que NÃO decide |
|---|---|---|
| **Solicitante** | O quê, quanto, para quê (justificativa) | Fornecedor, preço, forma de pagamento |
| **Compras** | Fornecedor, preço unitário, condição comercial, frete/desconto — monta o Pedido a partir da Requisição | Se o pedido é autorizado; como/quando paga |
| **Aprovador** | Autoriza ou rejeita o Pedido montado por Compras — **sim/não, ponto final** | Fornecedor, preço, conta, parcelas |
| **Financeiro** | Conta de pagamento, parcelas, se já efetivou — registra o Pagamento, a qualquer momento após o pedido aprovado | Se o pedido é válido; o que foi recebido |
| **Suprimentos** | Confere o que chegou fisicamente, número de série, nota fiscal — registra o Recebimento | Fornecedor, preço, pagamento |

**Hoje, uma pessoa só (você) cobre os cinco papéis.** A tela não vai virar
cinco telas — continua uma tela por pedido, com quatro ações possíveis nela
(Aprovar, Registrar pagamento, Registrar recebimento), cada uma habilitada
conforme o estado do pedido. O que muda é o nome e o *dono* de cada ação
ficarem inequívocos, prontos para o dia em que outra pessoa tocar uma delas.

> Nota sobre o que já existe: hoje `aprovar_requisicao_compra` funde Compras
> (escolher fornecedor/preço) com Aprovador (autorizar) num único clique —
> porque é a mesma pessoa. Pela tabela da seção 2 (Compras = negocia/cota/faz
> pedido; Aprovador = só aprova ou rejeita), o modelo correto é **separar os
> dois mesmo hoje**: Compras monta o Pedido (fornecedor, preço, condição) e
> só depois o Aprovador vê esse pedido pronto e decide sim/não — sem poder
> mexer em nenhum valor. Com uma pessoa só, ela passa pelos dois passos
> (monta → aprova o que ela mesma montou), mas o sistema já registra cada
> decisão com o papel certo, pronto para quando forem pessoas diferentes.

## 3. Status — dois eixos, não uma linha

O pedido **não** tem um único status linear. Ele tem **dois fatos
independentes**, porque pagamento e recebimento não têm ordem fixa:

```
                    PAGO?
                 não ──────── sim
RECEBIDO?  não   [A]          [B]
           sim   [C]          [D]
```

- **[A]** Aprovado, nada ainda — pedido normal em andamento.
- **[B]** Pago, mercadoria a caminho — é o caso que disparou esta conversa
  (cartão cobrado, câmera ainda não chegou).
- **[C]** Chegou, ainda não foi pago — boleto pago só na entrega.
- **[D]** Pago e recebido — pedido fechado, sem pendência.

Guardar isso como **um enum só** (`rascunho`, `aguardando_aprovacao`, ...)
obrigaria escolher uma ordem fixa entre pagar e receber, que não existe na
prática. A tabela abaixo é a tradução — para a tela e para você — dos dois
fatos reais (`compras.status` de recebimento + existência/status do
lançamento de pagamento) num rótulo único e legível:

| Rótulo na tela | Requisição | Pedido negociado (Compras) | `compras.status` | Pagamento | Situação |
|---|---|---|---|---|---|
| Rascunho | — | — | — | — | Fora do banco ainda (formulário aberto) |
| Aguardando aprovação (requisição) | `pendente` | — | — | — | Requisição criada, ninguém decidiu se vale a pena |
| Rejeitado | `rejeitada` | — | — | — | Fim de linha |
| Aguardando cotação (Compras) | `aprovada` | não | — | — | Requisição validada; falta Compras negociar fornecedor/preço |
| Aguardando aprovação (pedido) | `aprovada` | sim, rascunho | — | — | Compras montou o pedido; falta o Aprovador decidir sim/não |
| Aprovado | `convertida` | sim | `aberto` | nenhum | = **[A]** |
| Aguardando pagamento | `convertida` | sim | `aberto`/`recebido_parcial` | nenhum | = **[A]**/**[C]**, foco no financeiro |
| Pago, aguardando mercadoria | `convertida` | sim | `aberto`/`recebido_parcial` | previsto ou efetivado | = **[B]** |
| Recebido, aguardando pagamento | `convertida` | sim | `recebido` | nenhum | = **[C]** completo |
| Encerrado | `convertida` | sim | `recebido` | previsto ou efetivado | = **[D]** |
| Cancelado | qualquer | — | `cancelado` | (lançamento, se houver, é estornado) | Fim de linha |

> **Isto muda o schema atual**: hoje `aprovar_requisicao_compra` cria a linha
> em `compras` já aprovada, num passo só. Separar Compras de Aprovador de
> verdade exige um pedido "rascunho" existir *antes* da aprovação — ou um
> novo status em `status_pedido_compra` (`rascunho`), ou duas tabelas
> (proposta → pedido). Ponto em aberto de arquitetura: decido a abordagem
> quando este modelo for aprovado, a menos que você já tenha preferência.

Nenhuma coluna nova de "status combinado" no banco — o rótulo é calculado na
tela a partir dos dois campos que já existem (`compras.status` e
`compras.lancamento_id` → `lancamentos.status`). Evita o risco clássico de
um enum combinado ficar dessincronizado da realidade.

## 4. Visão por papel (o que cada um vê na tela)

Continua **um módulo só** (`/compras`), sem telas separadas por papel — mas
os filtros e a ação em destaque mudam pra cada um:

| Papel | O que vê primeiro | Ação em destaque |
|---|---|---|
| Solicitante | Minhas requisições (status delas) | Nova requisição |
| Compras | Requisições validadas sem pedido negociado ("Aguardando cotação") | Negociar / Montar pedido |
| Aprovador | Pedidos montados aguardando aprovação | Aprovar / Rejeitar |
| Financeiro | Pedidos aprovados sem pagamento registrado ("Aguardando pagamento") | Registrar pagamento |
| Suprimentos | Pedidos pagos ou aprovados sem recebimento total ("Aguardando mercadoria") | Registrar recebimento |

Hoje, com uma pessoa só, isso é só uma questão de o Dashboard/lista de
Pedidos trazer contadores por essas categorias ("3 aguardando pagamento",
"1 aguardando mercadoria") em vez de só "status do pedido" — dá pra você
mesmo usar como checklist, e já nasce pronto pro dia de ter mais gente.

## 5. Nomenclatura (resolvendo a confusão apontada)

| Ação | Nome na tela | Quem faz |
|---|---|---|
| Criar a necessidade | **Nova requisição** | Solicitante |
| Autorizar o pedido | **Aprovar pedido** | Aprovador |
| Rejeitar | **Rejeitar pedido** | Aprovador |
| Criar o compromisso financeiro | **Registrar pagamento** | Financeiro |
| Confirmar chegada física | **Registrar recebimento** | Suprimentos |
| Encerrar sem pendência | (automático — some da lista quando [D]) | — |

Nada de "efetivar", "baixar", "dar entrada" como sinônimos soltos — cada
documento tem exatamente um verbo.

## 6. O que muda da Etapa 55 (docs/59) — diff honesto

- **Mantém**: Requisição, Pedido, Recebimento como hoje; motor financeiro
  único (`criar_lancamento`); regra "compra não grava nada sozinha".
- **Muda**: Pagamento vira ação própria (`registrar_pagamento_compra`),
  podendo acontecer antes do Recebimento. `compras` ganha `lancamento_id`.
  `registrar_recebimento_compra` para de criar lançamento quando o pedido já
  foi pago — só confere item físico e dá entrada em estoque/patrimônio.
- **Muda também**: Compras (negocia/monta o pedido) e Aprovador (aprova o
  que Compras montou) viram dois passos distintos — hoje a mesma pessoa
  passa pelos dois, mas cada um fica registrado com seu papel certo.
- **Novo**: visão consolidada "Aguardando cotação" / "Aguardando aprovação"
  / "Aguardando pagamento" / "Aguardando mercadoria", e o selo
  correspondente em Financeiro → Lançamentos.

## 7. Plano de implementação (se aprovado)

Dado o tamanho, proponho **duas etapas** em vez de uma só — cada uma
entregável e testável sozinha:

**Etapa 64A — Pagamento separado do recebimento** (menor, já com o código
pronto da tentativa anterior, só precisa revisão):
1. `compras.lancamento_id` + `registrar_pagamento_compra` (Financeiro).
2. `registrar_recebimento_compra` ajustada: reaproveita o lançamento se já
   existir; senão, cria como hoje (caso boleto pago na entrega — sem
   regressão).
3. Tela do Pedido: rótulo combinado da seção 3, botão **Registrar pagamento**
   ao lado de **Registrar recebimento**, cada um habilitado conforme o caso.
4. Selo "Aguardando mercadoria" em Lançamentos (Financeiro).

**Etapa 64B — Compras separado do Aprovador** (maior, mexe em schema):
1. Resolver o ponto em aberto da seção 3 (status `rascunho` no pedido, ou
   tabela de proposta) para existir um "pedido montado, não aprovado".
2. `negociar_pedido_compra` (Compras: fornecedor, preço, condição, a partir
   da requisição aprovada) separado de `aprovar_pedido_compra` (Aprovador:
   só sim/não).
3. Tela: aba/filtro "Aguardando cotação" pro Compras, "Aguardando aprovação"
   pro Aprovador.

Ambas atualizam `docs/59-compras.md` (novas subseções 55D/55E). Aguardo sua
revisão deste modelo — e se topa dividir assim ou prefere tudo numa entrega
só — antes de eu retomar a implementação.
