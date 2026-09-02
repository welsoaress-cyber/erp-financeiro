# Etapa 6C — Planos e contratos

Status: **implementada e testada localmente (02/09/2026); aguardando aplicação da migration em produção e validação do proprietário.**

## 1. O que existe

### Banco (`supabase/migrations/20260902000008_planos_contratos.sql`)
| Objeto | Função |
|---|---|
| `periodicidade` (mensal/anual/unico), `status_contrato` (ativo/suspenso/encerrado) | Enums |
| `planos` | Catálogo de um negócio: `nome` (único por negócio), `descricao`, `valor_tabela` ≥ 0, `periodicidade`, `ativo`. Negócio imutável; negócio precisa estar ativo ao criar/reativar. Plano inativo não aceita contratos novos. |
| `contratos` | `negocio_id`, `pessoa_id`, `plano_id`, `codigo` (sequencial por negócio, com lock), `valor` negociado, `periodicidade`, `data_inicio`, `data_fim`, `dia_vencimento` (1–31), `status`, `observacao`. Constraints: encerrado ⇔ tem `data_fim`; `data_fim ≥ data_inicio`. |
| `tg_contratos_protecao` | Ao criar: plano do mesmo negócio e ativo, pessoa ativa, negócio ativo, nunca nasce encerrado. Ao alterar: encerrado é imutável; pessoa, negócio, plano e código não mudam. |
| `tg_contratos_vinculo` | Ao abrir contrato, cria (ou reativa) o vínculo **cliente** da pessoa com o negócio. |
| `lancamentos.contrato_id` + `tg_lancamentos_contrato` | Lançamento com contrato **herda** negócio e pessoa se vazios; divergência é erro; transferência não aceita contrato. |
| Negócio / Pessoa | Não podem ser inativados com contratos vigentes (ativo ou suspenso). |
| Motor | `criar_lancamento`/`atualizar_lancamento` ganham `p_contrato_id` (13º parâmetro). |
| `vw_resultado_por_contrato` | Receitas, despesas, resultado, nº de lançamentos e datas, só efetivados vinculados ao contrato. |
| `vw_receita_recorrente` | Por negócio: contratos ativos, suspensos e **MRR** (mensal = valor; anual = valor/12; único = 0; só ativos). |
| RLS, grants, auditoria | Padrão; sem DELETE. |

### App
| Onde | Conteúdo |
|---|---|
| Negócios → editar negócio | Seção **Planos e serviços**: lista, novo plano (nome, valor de tabela, periodicidade, descrição), editar, ativar/inativar |
| Menu **Contratos** | Cartões de receita recorrente por negócio; filtros por negócio e status (padrão: ativos); tabela com código, pessoa, plano, vencimento, valor, resultado e status |
| Novo contrato | Negócio → pessoa (vínculo automático) → plano (valor e periodicidade preenchidos, negociáveis) → início e dia de vencimento |
| Detalhe do contrato | Rentabilidade (receitas, despesas, resultado, nº de lançamentos), edição de valor/vencimento/observação, **suspender / reativar / encerrar com data**; encerrado somente leitura |
| Lançamentos | Campo **Contrato (opcional)** filtrado pelo negócio; ao escolher, negócio e pessoa seguem o contrato (pessoa travada); código do contrato na linha |
| Núcleo | Modal passa a rolar internamente (`max-h 90vh`), necessário com formulários mais longos |

## 2. Decisões técnicas
1. **Escrita direta com triggers**, sem funções de motor para contratos: as regras de estado cabem em trigger e a tabela não gera movimentos financeiros. Funções ficam reservadas ao ledger.
2. **Código sequencial por negócio** (#001, #002…), gerado no banco com lock transacional.
3. **Pessoa, negócio e plano imutáveis** no contrato. Mudança de plano = encerrar e abrir outro, preservando a rentabilidade histórica de cada um.
4. **MRR ignora contratos suspensos e planos de pagamento único**; anual entra dividido por 12.
5. **Faturamento recorrente automático** (gerar previstos mensais do contrato) fica para a Etapa 7, como aprovado. Hoje a receita do contrato é lançada manualmente com o contrato selecionado.

## 3. Testes realizados
| Teste | Resultado |
|---|---|
| SQL T1 planos: nome único por negócio, negócio imutável | OK |
| T2 contratos: códigos sequenciais por negócio, vínculo cliente automático, plano de outro negócio, plano inativo, criar encerrado | OK |
| T3 MRR: mensal + anual/12; suspenso não conta | OK |
| T4 lançamento com contrato herda negócio/pessoa; divergência de negócio e de pessoa; transferência com contrato | OK |
| T5 rentabilidade por contrato | OK |
| T6 ciclo: suspender/reativar, encerrar exige data, encerrado imutável, campos imutáveis | OK |
| T7 negócio e pessoa com contratos vigentes não inativam | OK |
| T8 RLS e DELETE | OK |
| Suítes anteriores (8) e `verificar_rls` (12 tabelas); `verificar_contratos.sql` 7 de 7 | OK |
| Lint, typecheck, build | OK |
| Interface: sem planos → aviso; planos no negócio (criar, duplicado); abrir contrato com valor do plano; MRR; vínculo automático; lançamento com contrato (herança e trava); código na linha; rentabilidade na lista e no detalhe; suspender (MRR zera), reativar, encerrar somente leitura | 19 de 19 |
| Regressões Negócios 20/20, Pessoas 16/16, Lançamentos 24/24, Contas 11/11, Categorias 14/14 | OK |

## 4. Aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000008_planos_contratos.sql` → Run.
2. SQL Editor → `supabase/tests/verificar_contratos.sql` → esperado `7 de 7 verificações OK`.
3. Site: Negócios → SERVNET → novo plano; Contratos → novo contrato para a pessoa cadastrada; Lançamentos → receita com o contrato; Contratos → conferir resultado e receita recorrente.
