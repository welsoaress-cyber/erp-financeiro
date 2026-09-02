# Etapa 6A — Negócios

Status: **implementada e testada localmente (02/09/2026); aguardando aplicação da migration em produção e validação do proprietário.**

## 1. O que existe

### Banco (`supabase/migrations/20260902000006_negocios.sql`)
| Objeto | Função |
|---|---|
| `negocios` | `id`, `organizacao_id`, `nome` (1–60), `slug` (`^[a-z0-9]+(-[a-z0-9]+)*$`, ≤ 40), `ativo`, `criado_em`, `atualizado_em`. Nome único (ignorando maiúsculas) e slug único por organização. |
| `lancamentos.negocio_id`, `contas.negocio_id` | Dimensão opcional. **Nulo = pessoal/central.** Índices por organização e negócio. |
| `tg_negocios_protecao` | Organização imutável; **inativar bloqueado** se houver lançamentos previstos pendentes ou contas ativas vinculadas. Histórico efetivado não impede. |
| `validar_negocio()` + triggers `contas_negocio` e `lancamentos_negocio` | Negócio da mesma organização; deve estar ativo ao vincular ou trocar. |
| `criar_lancamento` / `atualizar_lancamento` | Ganham `p_negocio_id` (11º parâmetro, opcional). A assinatura antiga foi removida. Transferência pode ter negócio (aporte/retirada). |
| `vw_saldo_contas` | Ganha `negocio_id`. |
| `vw_resultado_mensal_negocio` | Receitas, despesas e resultado por mês **e por negócio** (nulo = pessoal), só efetivados, sem transferências. `vw_resultado_mensal` consolidada permanece. |
| RLS, grants, auditoria | Padrão das etapas anteriores; sem DELETE. |

### App
| Módulo | Conteúdo |
|---|---|
| `modules/negocios` | Lista (nome, slug, status, filtro de inativos), criar (slug automático a partir do nome, editável), editar, inativar. `SelecaoNegocio` reutilizável com a opção "Pessoal". Item **Negócios** no menu. |
| `modules/lancamentos` | Campo Negócio no formulário (aparece só se houver negócios); filtro "Todos / Pessoal / negócio"; negócio na linha; novo lançamento herda o negócio do filtro. |
| `modules/contas` | Campo Negócio no formulário e coluna Negócio na lista. |
| `modules/dashboard` | Filtro "Todos / Pessoal / negócio" aplicado a saldo total, indicadores do mês, saldo por conta e últimas movimentações; bloco **Resultado por negócio** (visível em "Todos"). |

## 2. Decisões técnicas
1. **Inativar negócio** bloqueia só com previstos pendentes ou contas ativas; histórico efetivado é permitido. Difere da regra de Contas de propósito: um negócio encerrado precisa sair das listas sem perder o passado. **Precisa da sua aprovação.**
2. **Slug validado no banco** e gerado no app; único por organização. Será a chave estável para integrações e schemas por negócio.
3. **Sem negócio "Pessoal" artificial**: nulo = pessoal, conforme aprovado.
4. **Categorias por negócio**: fora, conforme indicado. Categorias seguem por organização.
5. Convenções mantidas (`criado_em`/`atualizado_em`).

## 3. Testes realizados
| Teste | Resultado |
|---|---|
| SQL T1 slug inválido, nome e slug duplicados | OK |
| T2 lançamentos com negócio e pessoais; transferência com negócio; views por negócio, consolidada e saldo da conta do negócio | OK |
| T3 trocar/remover negócio na edição; negócio inativo rejeitado | OK |
| T4 inativar bloqueado com previsto e com conta ativa; liberado após; vincular conta a negócio inativo rejeitado | OK |
| T5 RLS e DELETE negado | OK |
| T6 auditoria | OK |
| Suítes anteriores (Fundação, Contas, Segurança, Categorias, Lançamentos) e `verificar_rls` (8 tabelas) | OK |
| `verificar_negocios.sql` | 7 de 7 |
| Lint, typecheck, build | OK |
| Interface: negócios (slug automático, duplicado, editar), conta com negócio, lançamentos com negócio e filtros, dashboard (resultado por negócio, filtro, saldo do negócio), inativação bloqueada/liberada | 20 de 20 |
| Regressões Contas 11/11, Lançamentos 24/24, Categorias 14/14 | OK |

## 4. Aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000006_negocios.sql` → Run.
2. SQL Editor → `supabase/tests/verificar_negocios.sql` → esperado `7 de 7 verificações OK`.
3. Site: menu Negócios → cadastrar (ex.: SERVNET); Contas → vincular uma conta; Lançamentos → lançar com negócio; Dashboard → "Resultado por negócio" e filtro.
