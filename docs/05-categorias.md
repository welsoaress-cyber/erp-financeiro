# Etapa 4 — Categorias

Status: **CONCLUÍDA E VALIDADA EM PRODUÇÃO (02/09/2026).** Migration 0004 aplicada após limpeza de tabela externa; `verificar_categorias.sql` 9 de 9; categorias padrão visíveis no site.

## 1. O que existe

### Banco (`supabase/migrations/20260902000004_categorias.sql`)
| Objeto | Função |
|---|---|
| `tipo_categoria` (enum) | `receita`, `despesa` |
| `categorias` | `id`, `organizacao_id`, `nome` (1–60), `tipo`, `categoria_pai_id` (nulo = principal), `ativo`, `criado_em`, `atualizado_em` |
| índice único `(organizacao_id, tipo, lower(btrim(nome)))` | Nome único por tipo dentro da organização, ignorando maiúsculas e espaços. "Outros" pode existir em receita e em despesa. |
| `categoria_possui_lancamentos(uuid)` | Preparada para a Etapa 5: `false` enquanto `lancamentos` não existir; passa a valer sozinha depois. |
| `tg_categorias_protecao` (before insert/update) | Regras abaixo, com mensagens em português exibidas na tela. |
| `criar_categorias_padrao(uuid)` | Cria as 11 categorias padrão da organização (idempotente). Chamada pelo trigger de signup e, na migration, uma vez para as organizações existentes. |
| `tg_novo_usuario` (atualizada) | Signup agora cria organização + membro + categorias padrão. |
| RLS | `select/insert/update` por organização; **sem DELETE**. Auditoria e `atualizado_em` como nas demais tabelas. |

Categorias padrão: **Receitas** Salário, Rendimento, Investimento, Outros. **Despesas** Alimentação, Moradia, Transporte, Lazer, Saúde, Educação, Outros.

### Regras impostas pelo banco
1. Tipo imutável; organização imutável.
2. Categoria pai deve existir, ser da mesma organização e **do mesmo tipo**.
3. **Apenas 2 níveis**: uma subcategoria não pode ser pai; uma categoria com subcategorias não pode virar subcategoria.
4. Pai deve estar ativo ao vincular; subcategoria não pode ser reativada com pai inativo.
5. Não inativa com subcategorias ativas.
6. Não inativa com lançamentos (Etapa 5).
7. Exclusão física impossível pelo cliente.

### App (`app/src/modules/categorias/`)
| Arquivo | Função |
|---|---|
| `tipos.ts` | Tipos, rótulos e `montarArvore()` (raízes com filhas, ordem alfabética pt-BR) |
| `api.ts` | `useCategorias`, `useCriarCategoria`, `useAtualizarCategoria` (nunca envia `tipo`) |
| `components/FormularioCategoria.tsx` | Nome, Tipo (desabilitado na edição), Categoria pai opcional (só raízes ativas do mesmo tipo, excluindo a própria; desabilitado quando a categoria tem filhas), checkbox "Categoria ativa" na edição |
| `pages/CategoriasPage.tsx` | Abas Receitas/Despesas, contagem, filtro "Mostrar inativas", lista hierárquica com "└" nas subcategorias, atalho "+ subcategoria" em cada raiz ativa, clique abre edição em modal |

## 2. Decisões técnicas
1. **Dois níveis no máximo**, imposto no banco. Motivo: relatórios e seletores simples; árvores profundas eram fonte de confusão no sistema anterior.
2. **Unicidade por (organização, tipo, nome)** conforme solicitado, e não por pai. Efeito: não existem duas "Outros" dentro de despesa, mesmo sob pais diferentes. Simplifica seleção em lançamentos.
3. **Categorias padrão via função no banco**, não pela interface. Toda organização nasce pronta para uso; o app não decide dados iniciais.
4. **Inativação em cascata não é automática**: para inativar um pai, o usuário inativa as filhas antes. Evita efeitos invisíveis.
5. Sem coluna `ordem`: ordenação alfabética. Reordenação manual só se houver demanda.

## 3. Testes realizados
| Teste | Como | Resultado |
|---|---|---|
| T1 padrão criado para organização existente (backfill) e nova (signup): 11 cada | `categorias_test.sql`, Postgres 16 local | OK |
| T2 RLS: usuário vê só as suas | SQL | OK |
| T3 subcategoria válida; duplicada; pai de outro tipo; 3º nível; tipo imutável; pai com filhas virar sub | SQL | OK |
| T4 inativar pai com filha ativa bloqueado; inativar filha e pai; reativar filha com pai inativo bloqueado | SQL | OK |
| T5 editar nome e trocar pai | SQL | OK |
| T6 DELETE negado; insert em organização alheia negado | SQL | OK |
| T7 com `lancamentos` simulada: inativar bloqueado, renomear permitido | SQL | OK |
| T8 auditoria com `usuario_id` | SQL | OK |
| `verificar_categorias.sql` 9 de 9; `verificar_rls.sql` ok nas 5 tabelas | SQL | OK |
| Lint, typecheck, build | npm | OK |
| Interface ponta a ponta: 7 despesas padrão → filtro receitas 4 → atalho pré-seleciona pai → pais só do mesmo tipo → criar sub → hierarquia → duplicada bloqueada → tipo desabilitado → renomear → inativar pai bloqueado → inativar filha e pai → filtro inativas | Playwright + mock | 14 de 14 |
| Regressão Contas e2e | Playwright + mock | 11 de 11 |

## 4. Aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000004_categorias.sql` → Run. A própria migration cria as 11 categorias padrão na sua organização.
2. SQL Editor → `supabase/tests/verificar_categorias.sql` → esperado `9 de 9 verificações OK`.
3. Site → menu Categorias.
