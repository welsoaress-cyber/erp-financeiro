# ERP Financeiro Pessoal — Etapa 1: Arquitetura

Status: **aprovado em 02/09/2026; revisado em 02/09/2026 para a visão de plataforma multi-projeto (seção 11)**. Projeto novo, independente do sistema legado deste repositório (nada é reaproveitado).

---

## 1. Visão geral da arquitetura

### 1.1 Princípio central
O sistema é um **livro-razão (ledger) pessoal**. Tudo que altera dinheiro passa por um único motor: o **Lançamento**. Nenhuma tela grava saldo. Saldo, receitas, despesas e resultado são sempre **calculados** a partir dos lançamentos efetivados. Isso elimina divergência entre telas e impede saldo digitado manualmente.

### 1.2 Camadas

```
┌──────────────────────────────────────────────────────┐
│ UI (React + TypeScript)                              │
│  módulos de tela: dashboard, lançamentos, contas...  │
├──────────────────────────────────────────────────────┤
│ Camada de aplicação (TypeScript)                     │
│  casos de uso por módulo, validação, formatação      │
├──────────────────────────────────────────────────────┤
│ Motor financeiro (PostgreSQL)                        │
│  tabelas, constraints, funções atômicas, views de    │
│  saldo, auditoria, RLS por usuário                   │
└──────────────────────────────────────────────────────┘
```

**Decisão:** as regras de integridade financeira vivem **no banco** (constraints, funções transacionais, views). A UI nunca é a única guardiã de uma regra. Motivo: futuras integrações (importação de extrato, automações, API) usam o mesmo motor e não conseguem burlar as regras.

### 1.3 Stack

| Camada | Escolha | Justificativa |
|---|---|---|
| Banco | PostgreSQL via **Supabase** (projeto **novo**, separado do legado) | Constraints, funções, views, RLS, auth pronta, custo zero no início |
| Frontend | **React + TypeScript + Vite**, TanStack Query, Tailwind | Estrutura por módulos, tipagem forte, build estático barato |
| Hospedagem | Netlify (já existente na conta) | Custo zero |
| Backend próprio | **Nenhum** no MVP | Supabase client + funções SQL (RPC) para operações atômicas. Um backend só entra quando houver integração externa |

### 1.4 Organização do código (por módulo, não por tipo de arquivo)

```
erp-financeiro/
├── docs/                    # decisões de arquitetura
├── supabase/
│   └── migrations/          # esquema versionado, uma migration por etapa
└── app/
    └── src/
        ├── core/            # auth, cliente supabase, dinheiro, datas, layout
        ├── modules/
        │   ├── contas/
        │   ├── categorias/
        │   ├── lancamentos/
        │   └── dashboard/
        └── app/             # roteamento, menu, registro de módulos
```

Cada módulo contém suas telas, consultas, tipos e regras de apresentação. Um módulo só conversa com outro por interfaces públicas (`modules/contas/index.ts`), nunca importando arquivos internos.

---

## 2. Módulos

| # | Módulo | Prioridade | Depende de | Observação |
|---|---|---|---|---|
| 1 | **Núcleo** (auth, organização, auditoria) | Essencial | — | Invisível ao usuário |
| 2 | **Contas** | Essencial (MVP) | Núcleo | Contas bancárias, dinheiro, carteira |
| 3 | **Categorias** | Essencial (MVP) | Núcleo | Hierárquicas desde o início |
| 4 | **Lançamentos** | Essencial (MVP) — **coração** | Contas, Categorias | Receita, despesa, transferência |
| 5 | **Dashboard** | Essencial (MVP) | Lançamentos | Só leitura |
| 6 | Contas a Pagar / Receber | Fase 2 | Lançamentos | **Não é tabela nova**: são lançamentos com status `previsto`. Vira uma tela/visão |
| 7 | Cartões de Crédito | Fase 2 | Contas, Lançamentos | Cartão = conta do tipo `cartao_credito` + entidade Fatura |
| 8 | Centros de Custo | Fase 2 | Lançamentos | Dimensão opcional do lançamento |
| 9 | Orçamento | Fase 2 | Categorias, Lançamentos | Meta por categoria × mês; realizado vem do ledger |
| 10 | Relatórios | Fase 2 | Lançamentos | Views SQL, sem lógica nova |
| 11 | Importação de extratos / Conciliação | Fase 3 | Contas, Lançamentos | Extrato importado ↔ movimento |
| 12 | Empréstimos e Financiamentos | Fase 3 | Contas, Lançamentos | Contrato gera parcelas como lançamentos previstos |
| 13 | Patrimônio | Fase 3 | Contas | Bens + contas = patrimônio líquido |
| 14 | Investimentos | Fase 3 | Contas, Patrimônio | Conta tipo `investimento` + posições |
| 15 | Planejamento / Indicadores | Fase 4 | Tudo acima | Projeção usa lançamentos previstos |
| 16 | Configurações | Essencial (mínimo) | Núcleo | Perfil, preferências |

Regra de dependência: **nenhum módulo grava fora do motor de lançamentos**. Cartão, empréstimo, orçamento e importação **produzem ou leem lançamentos**; não criam saldos paralelos.

---

## 3. Núcleo financeiro

### 3.1 Modelo: Lançamento + Movimentos
Um **Lançamento** é o evento de negócio (o que aconteceu). Um **Movimento** é o efeito em uma conta (quanto entrou/saiu de onde).

| Tipo | Movimentos gerados | Categoria |
|---|---|---|
| Receita | 1 movimento **positivo** na conta | Obrigatória (tipo receita) |
| Despesa | 1 movimento **negativo** na conta | Obrigatória (tipo despesa) |
| Transferência | 2 movimentos: **−valor** na origem, **+valor** no destino, na mesma transação SQL | **Nula** (nunca entra em receita/despesa) |

Consequências diretas:
- Saldo de uma conta = `saldo_inicial + Σ movimentos efetivados`.
- Receitas/despesas do período = Σ lançamentos efetivados por tipo. Transferência fica de fora por construção.
- Cartão, parcelamento, empréstimo, importação: tudo cabe nesse modelo sem alterá-lo.

### 3.2 Estados do lançamento

```
previsto ──► efetivado ──► (edição auditada)
   │
   └──► cancelado
```

- **previsto**: agendado / a pagar / a receber. Não afeta saldo real. Afeta saldo **projetado**.
- **efetivado**: pago / recebido. Afeta saldo real.
- **cancelado**: preservado para histórico; não afeta nada. **Não existe exclusão física** de lançamento que já foi efetivado.

### 3.3 Datas (três, com papéis distintos)

| Campo | Significado | Uso |
|---|---|---|
| `data_competencia` | Quando o fato ocorreu (compra, salário) | Relatórios por competência, orçamento |
| `data_vencimento` | Quando deve ser pago/recebido | Contas a pagar/receber, alertas |
| `data_efetivacao` | Quando o dinheiro realmente moveu | **Saldo**, fluxo de caixa |

No MVP, o formulário preenche as três com a mesma data por padrão; o usuário só altera se precisar. A estrutura já suporta cartão e vencimentos sem migração.

---

## 4. Banco de dados (entidades principais)

Convenções: chave `uuid`; `criado_em`, `atualizado_em` em tudo; valores em `numeric(14,2)`; toda tabela de negócio tem `organizacao_id` protegido por RLS.

### 4.1 Núcleo
- **organizacoes** — o escopo raiz dos dados: a sua holding. Tudo (finanças pessoais e, no futuro, cada projeto/operação) vive dentro de **uma** organização. Existe desde o início para permitir múltiplos usuários **sem migrar dados**. *(Nome revisado na seção 11: antes chamava-se `entidades`; o termo foi liberado para não colidir com "entidade central de pessoa/cliente".)*
- **organizacao_membros** — `organizacao_id`, `usuario_id` (auth), `papel`.
- **auditoria** — `tabela`, `registro_id`, `acao`, `dados_antes`, `dados_depois`, `usuario_id`, `quando`. Preenchida por trigger.

### 4.2 Cadastros
- **contas** — `nome`, `tipo` (corrente, poupanca, dinheiro, carteira_digital, investimento, cartao_credito*), `saldo_inicial`, `data_inicio`, `moeda` (BRL), `ativo`, `cor/icone`.
  Regras: não pode ser excluída se possuir movimentos (apenas inativada); `saldo_inicial` só editável enquanto não houver movimentos (após isso, ajuste vira lançamento).
  *`cartao_credito` reservado, habilitado na Fase 2.
- **categorias** — `nome`, `tipo` (receita | despesa), `categoria_pai_id` (nula = raiz), `ativo`, `ordem`, `sistema` (bool, protege categorias internas como "Ajuste de saldo").
  Regras: filha herda o tipo do pai; inativa não aparece em novos lançamentos mas permanece no histórico.

### 4.3 Motor
- **lancamentos** — `tipo` (receita | despesa | transferencia), `descricao`, `valor` (> 0 sempre; o sinal é do movimento), `data_competencia`, `data_vencimento`, `data_efetivacao` (nula se previsto), `status` (previsto | efetivado | cancelado), `categoria_id` (obrigatória para receita/despesa, **nula obrigatoriamente** para transferência — constraint), `observacao`, `origem` (manual | importacao | recorrencia | sistema — reservado).
- **movimentos** — `lancamento_id`, `conta_id`, `valor` (com sinal), `data` (= data_efetivacao).
  Regras (constraints/trigger): receita/despesa têm exatamente 1 movimento; transferência tem exatamente 2, com contas distintas e soma zero; movimentos só existem para lançamentos `efetivado`.

### 4.4 Consultas derivadas (views)
- **vw_saldo_contas** — saldo real por conta.
- **vw_saldo_projetado** — saldo real + previstos até uma data.
- **vw_resultado_periodo** — receitas, despesas e resultado por mês (exclui transferências por construção).

### 4.5 Relacionamentos

```
organizacoes 1──n contas
organizacoes 1──n categorias (categorias n──1 categorias  [pai])
organizacoes 1──n lancamentos n──1 categorias
lancamentos 1──n movimentos n──1 contas
```

### 4.6 Reservado para fases futuras (não criado agora)
`cartoes_faturas`, `centros_custo`, `orcamentos`, `recorrencias`, `extratos_importados`, `conciliacoes`, `contratos_emprestimo`, `bens_patrimonio`, `posicoes_investimento`, `anexos`, `tags`. Todos se ligam a `lancamentos`/`contas` existentes; nenhum exige alterar o núcleo. As tabelas da plataforma multi-projeto (`projetos`, `pessoas`, `pessoa_projeto_vinculos`, `canais`, `integracoes`) estão na seção 11.

---

## 5. Regras fundamentais do motor financeiro

1. **Saldo nunca é gravado.** É `saldo_inicial + Σ movimentos efetivados`. Se um dia for necessário cache por performance, será materializado a partir do ledger e recalculável.
2. **Receita** = lançamento tipo receita + 1 movimento positivo. Exige categoria de receita.
3. **Despesa** = lançamento tipo despesa + 1 movimento negativo. Exige categoria de despesa.
4. **Transferência** = 1 lançamento + 2 movimentos criados em **uma função SQL atômica** (`registrar_transferencia`). Sem categoria. Nunca aparece em receita/despesa. Origem ≠ destino.
5. **Valor sempre positivo** no lançamento; o sinal pertence ao movimento. Evita erro de digitação de sinal.
6. **Previsto vs efetivado:** só o efetivado altera saldo real. Efetivar um previsto = preencher `data_efetivacao` e gerar movimentos (função `efetivar_lancamento`). "Contas a pagar" = despesas previstas; "contas a receber" = receitas previstas.
7. **Vencimento** é informação de controle, não de saldo. Atrasado = previsto com vencimento < hoje.
8. **Lançamentos futuros** entram como `previsto` com data futura. Dashboard mostra saldo real e, opcionalmente, projetado.
9. **Exclusão:** lançamento `previsto` pode ser excluído; `efetivado` só pode ser **cancelado** (auditado) ou editado (auditado). Conta e categoria com uso: apenas inativadas.
10. **Duplicidade:** aviso na UI quando existir lançamento com mesma conta, valor e data em ±1 dia; futura importação usará hash de extrato como chave única.
11. **Ajuste de saldo** (quando o usuário sabe o saldo real e o sistema diverge): nunca edita saldo; gera lançamento com categoria de sistema "Ajuste de saldo", rastreável.
12. **Datas** armazenadas como `date` (sem fuso); dinheiro em `numeric(14,2)` no banco e inteiro em centavos na UI para evitar erro de ponto flutuante.
13. **Toda mutação passa por função SQL ou pela tabela com constraints**; a UI não implementa regra que o banco não valide.

---

## 6. Navegação (MVP)

```
▣ Dashboard
▣ Lançamentos           (lista + filtro por período/conta/categoria/tipo; novo: receita | despesa | transferência)
▣ Contas
▣ Categorias
▣ Configurações
```

Estrutura futura do menu (grupos aparecem apenas quando o módulo existir):

```
Visão geral      Dashboard · Indicadores
Movimentação     Lançamentos · Contas a pagar · Contas a receber · Transferências
Cadastros        Contas · Cartões · Categorias · Centros de custo
Planejamento     Orçamento · Planejamento financeiro
Patrimônio       Patrimônio · Investimentos · Empréstimos e financiamentos
Relatórios       Relatórios · Conciliação · Importação
Configurações
```

Layout: barra lateral fixa à esquerda, cabeçalho com seletor de período (mês) global, conteúdo à direita. Sem gráficos além do essencial no MVP.

---

## 7. Evolução sem quebrar o existente

- **Núcleo estável:** `lancamentos` e `movimentos` não mudam de significado. Novos módulos adicionam tabelas que **apontam para** eles, não os alteram.
- **Migrations versionadas:** cada etapa = uma migration numerada; nunca se edita migration aplicada.
- **Módulos registrados:** o menu e as rotas são montados a partir de um registro (`app/modules.ts`). Adicionar módulo = adicionar pasta + uma linha no registro.
- **Contratos públicos por módulo:** um módulo expõe `index.ts`; outros só consomem isso.
- **Campos reservados já previstos:** `origem` no lançamento, tipo `cartao_credito` na conta, `organizacao_id` em tudo — evitam migrações de dados nas fases 2–3. Os campos de dimensão da plataforma (`projeto_id`, `pessoa_id`, `documento_tipo/documento_id`) são **colunas nulas adicionadas depois**, sem quebrar nada (seção 11.4).
- **Views como API de leitura:** relatórios e dashboards leem views; mudar a implementação interna não quebra telas.
- **Testes de regra no banco:** cada regra da seção 5 ganha um teste SQL (pgTAP) antes de o módulo ser considerado pronto.

---

## 8. Roadmap

| Etapa | Entrega | Critério de pronto |
|---|---|---|
| 1 | Arquitetura (este documento) | Aprovação sua |
| 2 | Fundação: projeto Supabase novo, app Vite, auth, `organizacoes`, `auditoria`, layout com menu, migration inicial | **Concluída em código (02/09/2026).** Pendente: projeto Supabase e conexão Cloudflare Pages |
| 3 | Contas | CRUD, inativação, saldo calculado por view (com saldo inicial) |
| 4 | Categorias | CRUD hierárquico, categorias padrão iniciais (semente) |
| 5 | Lançamentos | Receita, despesa, transferência atômica, previsto/efetivado, cancelamento auditado, filtros, aviso de duplicidade |
| 6 | Dashboard | Saldo total, receitas, despesas, resultado do período, últimas movimentações |
| 7+ | Fase 2 | Contas a pagar/receber (visão), cartões/faturas, orçamento, centros de custo, relatórios |
| — | Fase 3 | Importação/conciliação, empréstimos, patrimônio, investimentos |
| — | Fase 4 | Planejamento, indicadores, automações |

Sequência mantida como você propôs. Única troca sugerida: **Etapa 2 (Fundação) entra antes de Contas** porque auth, entidade e layout são pré-requisito de qualquer tela.

---

## 9. Definição do MVP

**Escopo:** Etapas 2 a 6. Contas, Categorias, Lançamentos (receita/despesa/transferência, previsto/efetivado) e Dashboard.

**Fora do MVP:** IA, automações, integração bancária, Open Finance, investimentos, conciliação, documentos, multiempresa, contabilidade, cartão de crédito (estrutura reservada, tela na Fase 2), recorrência (campo reservado, lógica na Fase 2).

**Pronto quando:** saldo de qualquer conta bate com `saldo_inicial + Σ movimentos` em qualquer tela; transferência não aparece como receita/despesa; lançamento efetivado não pode ser apagado; cadastros em uso não podem ser excluídos.

---

## 10. Decisões que precisam da sua confirmação

1. **Projeto Supabase novo** (separado do legado). Recomendado; evita contaminação de esquema e RLS. *(Aprovado.)*
2. **Pasta `erp-financeiro/` neste repositório** por enquanto. Se preferir, migro para repositório próprio na Etapa 2.
3. **Stack**: React + TypeScript + Vite + Supabase + Netlify.
4. **Modelo Lançamento + Movimentos** com transferência = 2 movimentos.
5. **Sem exclusão física** de lançamento efetivado (cancelamento auditado).

---

## 11. Revisão: plataforma central multi-projeto (02/09/2026)

Contexto recebido após a aprovação: o ERP deverá, no futuro, administrar várias operações (SERVNET, SERVIDOR, Navalha no Bigode, PRECAUTEC, PORTO ODONTO, outras) com um **cadastro central de pessoas**, financeiro centralizado e também separado por projeto, canais/telefones por projeto, integrações de pagamento e automações por projeto e portais por projeto. **Nada disso é implementado agora.** Esta seção fixa os conceitos e garante que a fundação não bloqueie essa evolução.

### 11.1 Conceitos (vocabulário definitivo)

| Conceito | Significado | Pertence a |
|---|---|---|
| **Organização** | Escopo raiz: a sua holding. Uma só, hoje. Contém finanças pessoais e todos os projetos. | Núcleo |
| **Negócio** (antes "Projeto / Operação") | Uma unidade de negócio: SERVNET, SERVIDOR, Navalha… Cadastro no núcleo; regras específicas em módulo próprio. Termo ajustado em 02/09/2026 para o vocabulário do proprietário. | Núcleo (o cadastro) / Módulo (as regras) |
| **Pessoa** | Cadastro único de pessoa física ou jurídica (cliente, fornecedor, contato). João existe **uma vez**. | Núcleo |
| **Vínculo** | Relação de uma pessoa com um projeto e um papel (João é *cliente* da SERVNET e do SERVIDOR). | Núcleo (o vínculo) |
| **Contrato / Plano / Serviço / Fatura** | O que a pessoa tem dentro de um projeto. Específico de cada operação. | Módulo de operação |
| **Canal** | Meio de comunicação identificado (número WhatsApp, e-mail, telefone) ligado a um projeto. | Núcleo (cadastro) / Comunicação (uso) |
| **Lançamento / Movimento / Conta** | Motor financeiro único, já aprovado. | Financeiro (núcleo) |

Regras: **o núcleo nunca depende de um projeto**; um projeto depende do núcleo; um projeto nunca depende de outro projeto; qualquer projeto pode ser removido sem tocar no núcleo.

### 11.2 Camadas da plataforma

```
┌─────────────────────────── MÓDULOS DE OPERAÇÃO (futuro) ───────────────────────────┐
│  servnet/        servidor/       navalha/        precautec/       portoodonto/       │
│  contratos       serviços        (integração)    …                …                  │
│  planos          faturas                                                             │
│  portal          portal                                                              │
└──────────────┬──────────────────────┬──────────────────────────────┬─────────────────┘
               │ usam                 │ geram lançamentos             │ usam
┌──────────────▼──────────────────────▼──────────────────────────────▼─────────────────┐
│ NÚCLEO DA PLATAFORMA                                                                 │
│  Organização · Projetos (cadastro) · Pessoas · Vínculos · Canais · Auditoria · Auth  │
│  FINANCEIRO: Contas · Categorias · Lançamentos · Movimentos                          │
│  (futuro) Comunicação · Integrações de pagamento · Automações · Conciliação          │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### 11.3 Entidades futuras do núcleo (não criar agora)

- **projetos** — `organizacao_id`, `nome`, `codigo` (ex.: `servnet`), `ativo`. O cadastro fica no núcleo; as regras ficam no módulo. Um projeto pode ter suas próprias contas bancárias (`contas.projeto_id`) ou usar contas centrais.
- **pessoas** — `organizacao_id`, `tipo` (física/jurídica), `nome`, `documento` (CPF/CNPJ, único por organização), `usuario_id` (nulo; preenchido quando a pessoa tiver login em um portal). Contatos (telefones, e-mails, endereços) em tabelas filhas.
- **pessoa_projeto_vinculos** — `pessoa_id`, `projeto_id`, `papel` (cliente, fornecedor, parceiro…), `status`, `desde`. Uma pessoa, N projetos.
- **canais** — `projeto_id`, `tipo` (whatsapp, email, telefone, site), `identificador` (o número/endereço), `ativo`. Responde "qual telefone pertence a qual projeto".
- **integracoes** — `projeto_id`, `provedor` (mercadopago, …), configuração. Eventos recebidos (pagamentos) entram numa tabela própria e são **conciliados** com lançamentos; nunca criam saldo por fora.
- **comunicacoes** — `projeto_id`, `pessoa_id`, `canal_id`, `referencia` (documento que originou), conteúdo, direção, status. Base para automações "3 dias antes / no dia / 3 dias depois".

### 11.4 Extensões do motor financeiro (colunas nulas, adicionadas quando o módulo chegar)

| Tabela | Coluna futura | Significado | Impacto |
|---|---|---|---|
| `lancamentos` | `projeto_id` (nulo) | A qual operação a receita/despesa pertence. Nulo = pessoal/central. | Dimensão de relatório; nenhuma regra de saldo muda |
| `lancamentos` | `pessoa_id` (nulo) | Contraparte (quem pagou / quem recebeu). | Contas a receber por cliente |
| `lancamentos` | `documento_tipo` + `documento_id` (nulos) | Documento gerador (fatura SERVNET, parcela de contrato…). Referência genérica, sem FK direta a tabelas de módulo. | Rastreabilidade sem acoplar o núcleo a um projeto |
| `contas` | `projeto_id` (nulo) | Conta bancária de uma operação. Nulo = central/pessoal. | Saldo por projeto = soma das contas do projeto |

Com isso: **financeiro centralizado** = todos os lançamentos da organização; **financeiro por projeto** = filtro por `projeto_id`; transferência entre conta pessoal e conta de projeto = transferência comum (2 movimentos), visível como aporte/retirada nos relatórios por projeto. O modelo Lançamento → Movimentos → Saldo **não muda**.

### 11.5 Portais e RLS

Usuários internos (você, futuros membros) e clientes de portal são populações diferentes. Regra: dados expostos a um portal ficam em **views dedicadas por projeto** (ex.: `servnet_portal.faturas`) com policies baseadas em `pessoas.usuario_id = auth.uid()`. As tabelas do núcleo continuam protegidas por `organizacao_membros`. Um cliente de portal **nunca** recebe policy nas tabelas do núcleo.

### 11.6 Organização do código por operação

- Banco: núcleo no schema `public`; cada operação em **schema próprio** (`servnet`, `servidor`, …) com FKs para `public.pessoas` / `public.projetos`. Remover um projeto = remover um schema.
- App: `src/modules/<nome>` para módulos do núcleo; `src/operacoes/<nome>` para módulos de operação, registrados no mesmo registro de módulos. Portais são **apps separados** (`portais/<nome>`), compartilhando o mesmo banco e o mesmo motor.

### 11.7 Verificação dos 11 requisitos

| # | Requisito | Situação |
|---|---|---|
| 1 | Múltiplos projetos/operações | `projetos` no núcleo + schema por operação. Permite. |
| 2 | Pessoa cliente de vários projetos | `pessoas` única + `pessoa_projeto_vinculos`. Permite. |
| 3 | Pessoa com vários contratos | Contratos no módulo da operação, N por vínculo. Permite. |
| 4 | Pessoa com vários planos/serviços | Idem, dentro do módulo. Permite. |
| 5 | Telefones/canais por projeto | `canais` com `projeto_id`. Permite. |
| 6 | Financeiro centralizado | Um ledger por organização. Já é assim. |
| 7 | Financeiro por projeto | `lancamentos.projeto_id` + `contas.projeto_id`. Permite. |
| 8 | Integrações de pagamento por projeto | `integracoes` por projeto + conciliação com lançamentos. Permite. |
| 9 | Automações por projeto | `comunicacoes` + regras por projeto. Permite. |
| 10 | Portais por projeto | Views/RLS dedicadas + app separado. Permite. |
| 11 | Novos projetos no futuro | Cadastro em `projetos` + novo schema + novo módulo registrado. Permite. |

### 11.8 O que muda no que já foi aprovado/construído

1. **Renomear** `entidades` → `organizacoes` e `entidade_membros` → `organizacao_membros`. **Aprovado e aplicado em 02/09/2026** (migration, testes e app; zero ocorrências antigas).
2. Nenhuma outra alteração na Fundação. Nenhuma tabela nova agora.
3. O MVP (Etapas 3–6) permanece exatamente igual.

### 11.9 Decisões fechadas (02/09/2026)
- Os dois pilares — **Organização → Projetos → Pessoas → Vínculos → Contratos/Planos/Serviços** e **Lançamento → Movimentos → Saldo** — são independentes e integráveis. **Nunca haverá um segundo motor financeiro** para projetos; projetos geram lançamentos no motor único.
- **Módulos de operação** (SERVNET, SERVIDOR, Navalha, PRECAUTEC, PORTO ODONTO), pessoas, vínculos, contratos, planos, faturas, boletos, Mercado Pago, WhatsApp, Oracle Code, portais, automações e integrações são **roadmap**. Não devem ser antecipados em nenhuma etapa do MVP.
- Hospedagem: **Cloudflare Pages, plano Free**, aprovado. Nenhum recurso pago sem autorização.
- Supabase: **plano gratuito**, sem upgrade automático, em **conta Supabase nova e exclusiva** (Opção A, 02/09/2026); nenhum projeto legado é alterado, pausado ou excluído.
- **Regra permanente de isolamento:** NOVO ERP = NOVO PROJETO + NOVO SUPABASE + BANCO ISOLADO. Integração futura com os sistemas existentes será por API, eventos ou mecanismo equivalente — **nunca** por compartilhamento direto de banco, tabelas ou migrations. Banco local serve apenas para testes, nunca como substituto definitivo.
