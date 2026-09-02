# Etapa 6 — Negócios, Pessoas, Planos e Contratos (PROPOSTA)

Status: **proposta para análise; nenhum código.** Só começa após a validação da Etapa 5 e a sua aprovação deste documento.

## 1. Objetivo
Saber **quanto cada contrato e cada negócio dá de resultado**, e não só a DRE consolidada. Isso exige que receitas e despesas carreguem duas dimensões novas: o **negócio** a que pertencem e, quando houver, o **contrato** (e portanto a pessoa) que as originou. O motor financeiro não muda: é o mesmo lançamento, com mais duas etiquetas.

## 2. Conceitos (vocabulário definitivo)
| Conceito | Definição | Exemplos |
|---|---|---|
| **Negócio** | Unidade de negócio da sua organização. Toda receita/despesa pode pertencer a um negócio; sem negócio = pessoal. | SERVNET, SERVIDOR, Navalha no Bigode, PRECAUTEC, PORTO ODONTO |
| **Pessoa** | Cadastro único de pessoa física ou jurídica. Existe **uma vez** na organização, independentemente de quantos negócios a atendem. | João da Silva (CPF), Empresa X (CNPJ) |
| **Vínculo** | Relação pessoa × negócio × papel. | João é *cliente* da SERVNET e do SERVIDOR; Fornecedor Y é *fornecedor* da SERVNET |
| **Plano** | Item do catálogo de um negócio: o que se vende, com preço de tabela e periodicidade. | SERVNET: "Fibra 500 Mbps" R$ 99,90/mês; SERVIDOR: "Hospedagem básica" R$ 49/mês |
| **Contrato** | Uma pessoa contratando um plano de um negócio, com valor negociado, vigência e dia de vencimento. Uma pessoa pode ter vários. | João: Contrato 001 (Fibra 500) + Contrato 002 (plano adicional) |

Regras de dependência: Pessoa não depende de negócio. Contrato depende de pessoa, negócio e plano. Lançamento pode apontar para negócio, e opcionalmente para contrato (que já carrega pessoa e negócio).

## 3. Modelo de dados (schema `public`, núcleo)

```
organizacoes ─1:N─ negocios ─1:N─ planos
     │                 │              │
     └─1:N─ pessoas ─N:M─┘ (vinculos)  │
                │                      │
                └────1:N── contratos ──┘   (pessoa + negócio + plano)
                                │
lancamentos ── negocio_id (nulo = pessoal) ── contrato_id (nulo) ── pessoa_id (nulo)
```

| Tabela | Campos principais | Regras no banco |
|---|---|---|
| `negocios` | nome, codigo (ex.: `servnet`, único), cor, ativo | inativar só sem contratos ativos |
| `pessoas` | tipo (fisica/juridica), nome, documento (CPF/CNPJ, único por organização, validado por dígito), email, telefone, observacao, ativo | documento opcional mas único quando informado; inativar só sem contratos ativos |
| `vinculos` | pessoa_id, negocio_id, papel (cliente/fornecedor/parceiro), desde, ativo | único por (pessoa, negócio, papel) |
| `planos` | negocio_id, nome, valor (tabela), periodicidade (mensal/anual/unico), ativo | nome único por negócio; inativar não afeta contratos existentes |
| `contratos` | negocio_id, pessoa_id, plano_id, codigo (sequencial por negócio), valor (negociado), periodicidade, data_inicio, data_fim, dia_vencimento (1–31), status (ativo/suspenso/encerrado), observacao | plano do mesmo negócio; pessoa com vínculo *cliente* no negócio (criado automaticamente se não existir); encerrar exige data_fim; encerrado é imutável |
| `lancamentos` (+3 colunas nulas) | `negocio_id`, `contrato_id`, `pessoa_id` | contrato ⇒ negocio e pessoa iguais aos do contrato; negócio ativo ao vincular; transferência pode ter negócio (aporte/retirada) mas nunca contrato |

Views novas:
- `vw_resultado_por_negocio` (mês, negócio): receitas, despesas, resultado. Lançamentos sem negócio aparecem como "Pessoal".
- `vw_resultado_por_contrato` (contrato): receitas, despesas diretas, resultado, meses ativos, ticket médio.
- `vw_contratos_ativos` (por negócio): contratos, receita mensal contratada (MRR), inadimplência prevista (previstos vencidos).

Tudo com RLS por organização, auditoria e sem DELETE, no padrão das etapas anteriores. Escrita em `contratos` passa por função do motor (`abrir_contrato`, `suspender_contrato`, `encerrar_contrato`) porque muda estado.

## 4. O que muda no que já existe
- Formulário de lançamento ganha **Negócio** (opcional; padrão = último usado) e, escolhido o negócio, **Contrato** (opcional, lista só contratos ativos do negócio). Pessoa é preenchida pelo contrato.
- Lista de lançamentos ganha filtro por negócio e coluna/etiqueta do negócio.
- Dashboard ganha um bloco "Resultado por negócio" no mês.
- Contas ganham `negocio_id` opcional (conta bancária da SERVNET, por exemplo), só como etiqueta: saldo continua por conta.

## 5. Fora desta etapa (roadmap)
- **Faturamento recorrente**: gerar automaticamente os lançamentos previstos mensais de cada contrato (Etapa 7). Na Etapa 6 a receita do contrato é lançada manualmente com o contrato selecionado.
- Boletos, Mercado Pago, WhatsApp/avisos de vencimento, portal do cliente, importação da base legada (101 clientes / 8 planos da SERVNET) — a importação pode ser a Etapa 6D, por CSV, **sem** acesso ao banco antigo.
- Regras específicas de cada negócio (status de rede da SERVNET, agendamento do Navalha) ficam em módulos/schemas próprios, depois.

## 6. Sub-etapas propostas (cada uma validada antes da próxima)
| Sub-etapa | Entrega | Critério de pronto |
|---|---|---|
| **6A Negócios** | Cadastro de negócios; `negocio_id` em lançamentos e contas; filtro e resultado por negócio no dashboard | Ver resultado do mês por negócio, com "Pessoal" separado |
| **6B Pessoas e vínculos** | Cadastro de pessoas (CPF/CNPJ validado), vínculos por negócio e papel | Uma pessoa vinculada a dois negócios sem duplicar cadastro |
| **6C Planos e contratos** | Catálogo por negócio, contratos com vigência e vencimento, `contrato_id`/`pessoa_id` em lançamentos, relatório de rentabilidade por contrato | Ver receitas, despesas e resultado de um contrato |
| **6D Importação (opcional)** | Importar clientes/planos/contratos da SERVNET por CSV | Base migrada sem tocar no banco legado |

## 7. Navegação
Menu passa a ter um grupo **Cadastros** (Contas, Categorias, Pessoas, Negócios) e **Contratos** como item próprio. Planos ficam dentro da tela do negócio.

## 8. Decisões que precisam da sua aprovação
1. Termo **Negócio** substitui "Projeto/Operação" na arquitetura (já ajustado no vocabulário).
2. Lançamento sem negócio = **pessoal**, sem criar um negócio "Pessoal" artificial.
3. Faturamento recorrente fica para a Etapa 7; na 6 o vínculo ao contrato é manual.
4. Ordem 6A → 6B → 6C → 6D.
