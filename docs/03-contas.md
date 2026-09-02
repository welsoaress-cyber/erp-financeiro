# Etapa 3 — Contas

Status: **CONCLUÍDA E VALIDADA EM PRODUÇÃO (02/09/2026).** Migration 0002 aplicada, `verificar_contas.sql` 9 de 9, `verificar_rls.sql` ok nas 4 tabelas; criar, editar e inativar conta confirmados pelo proprietário no site.

## 1. O que existe

### Banco (`supabase/migrations/20260902000002_contas.sql`)
| Objeto | Função |
|---|---|
| `tipo_conta` (enum) | `corrente`, `poupanca`, `dinheiro`, `carteira_digital`, `investimento`. Tipo inválido é rejeitado pelo próprio Postgres. `cartao_credito` será adicionado na Fase 2 com `alter type … add value`, sem migração de dados. |
| `contas` | `id`, `organizacao_id`, `nome` (1–80), `tipo`, `saldo_inicial` (≥ 0, default 0), `data_inicio` (default hoje), `ativo` (default true), `criado_em`, `atualizado_em`. **Não existe coluna de saldo.** |
| índice único `(organizacao_id, lower(btrim(nome)))` | Impede duas contas com o mesmo nome na organização, ignorando maiúsculas e espaços. |
| `conta_possui_movimentos(uuid)` | Responde se a conta tem lançamentos. Enquanto `movimentos` não existe (Etapa 5), responde `false`. Quando a tabela nascer, a regra passa a valer sem alterar `contas`. |
| `tg_contas_protecao` (before update) | Bloqueia: mudança de tipo; mudança de organização; alteração de `saldo_inicial`/`data_inicio` com movimentos; **inativação com movimentos**. Mensagens em português, exibidas na tela. |
| triggers `atualizado_em` e `auditoria` | Mesmos da Fundação. |
| RLS | `select`, `insert`, `update` restritos a `organizacao_id in (minhas_organizacoes())`. **Sem policy nem grant de DELETE**: exclusão física é impossível pelo cliente. |

### App (`app/src/modules/contas/`)
| Arquivo | Função |
|---|---|
| `tipos.ts` | Tipos e rótulos dos tipos de conta |
| `api.ts` | `useContas`, `useCriarConta`, `useAtualizarConta` (TanStack Query + Supabase). A atualização nunca envia `tipo`. |
| `components/FormularioConta.tsx` | Formulário de criar/editar com validação: nome obrigatório (≤ 80), saldo numérico ≥ 0, data obrigatória. Tipo desabilitado na edição. Checkbox "Conta ativa" só na edição. |
| `pages/ContasPage.tsx` | Lista (Nome, Tipo, Saldo inicial, **Saldo atual** desde a Etapa 5, Início, Status), botão "Nova conta", estado vazio, filtro "Mostrar inativas", clique na linha abre edição em modal. |

Componentes novos no núcleo, reutilizáveis pelos próximos módulos: `ui/Modal`, `ui/Selecao`, `ui/Distintivo`, `formatos/` (moeda BRL, data BR, hoje ISO). `mensagemDeErro` passou a traduzir códigos do Postgres (duplicidade, valor inválido, permissão, tabela inexistente).

## 2. Decisões técnicas
1. **Convenções da Fundação mantidas** em vez dos nomes sugeridos na solicitação (`created_at`, `status text`, `uuid_generate_v4()`): `criado_em/atualizado_em`, `ativo boolean`, `gen_random_uuid()`. Motivo: um único padrão em todo o esquema.
2. **Tipo como enum** e não `text`: validação no banco, não só na tela.
3. **Cartão de crédito fora** desta etapa, conforme solicitado; o enum é extensível.
4. **Saldo inicial ≥ 0** também no banco, conforme solicitado. Ressalva: conta corrente com cheque especial pode nascer negativa; se necessário, isso será tratado na Etapa 5 por lançamento de ajuste, não relaxando a regra.
5. **Inativação bloqueada quando há lançamentos**, conforme solicitado, com a verificação já no banco. **Ressalva arquitetural para a Etapa 5:** uma conta encerrada no banco real precisa poder ser inativada mesmo com histórico, senão fica para sempre nas listas de seleção. Recomendação a avaliar na Etapa 5: bloquear inativação apenas se houver lançamentos *previstos* (pendentes) na conta, e permitir com histórico *efetivado*. É uma linha no trigger.
6. **Nome único por organização** (case-insensitive): evita duplicidade acidental, problema recorrente citado na arquitetura.
7. **Renomear sempre permitido**, inclusive com movimentos: não afeta integridade.

## 3. Testes realizados
| Teste | Como | Resultado |
|---|---|---|
| T1 criar conta com defaults (saldo 0, hoje, ativa) | `supabase/tests/contas_test.sql` em Postgres 16 local | OK |
| T2 nome vazio, tipo inválido, saldo negativo, nome duplicado rejeitados pelo banco | SQL | OK |
| T3 editar nome/saldo sem movimentos; mudar tipo rejeitado | SQL | OK |
| T4 inativar e reativar sem movimentos | SQL | OK |
| T5 DELETE negado | SQL | OK |
| T6 RLS: outro usuário não vê nem cria conta na organização alheia | SQL | OK |
| T7 com tabela `movimentos` simulada: inativar e alterar saldo inicial bloqueados; renomear permitido | SQL | OK |
| T8 auditoria com `usuario_id` | SQL | OK |
| Fundação (T1–T6) reexecutada após a nova migration | SQL | OK |
| `verificar_contas.sql` | SQL | 9 de 9 |
| Typecheck, build, lint | npm | OK |
| Interface ponta a ponta: página vazia → validação nome → validação saldo → criar → listar com moeda/rótulo → duplicado bloqueado → editar (tipo desabilitado) → inativar → filtro de inativas | Playwright + Chromium + mock local da API | 11 de 11 |

Rodar localmente:
```
createdb erp_test
psql -d erp_test -f supabase/tests/00_shim_local.sql -f supabase/migrations/20260902000001_fundacao.sql -f supabase/migrations/20260902000002_contas.sql
psql -d erp_test -f supabase/tests/contas_test.sql   # OK
```

## 4. Aplicar em produção
1. SQL Editor → colar `supabase/migrations/20260902000002_contas.sql` → Run.
2. SQL Editor → colar `supabase/tests/verificar_contas.sql` → Run → esperado `9 de 9 verificações OK`.
3. O app já está publicado; a página Contas passa a funcionar assim que a migration existir (antes disso mostra "Estrutura do banco ainda não atualizada para este módulo").
