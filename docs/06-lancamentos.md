# Etapa 5 — Lançamentos (motor financeiro) e Dashboard

Status: **implementada e testada localmente (02/09/2026); aguardando aplicação da migration em produção e validação do proprietário.**

## 1. Modelo
```
LANÇAMENTO (evento)  ──1:N──▶  MOVIMENTO (efeito em uma conta, valor com sinal)
                                        │
        saldo da conta = saldo_inicial + Σ movimentos      (vw_saldo_contas)
```
| Tipo | Movimentos gerados na efetivação | Categoria |
|---|---|---|
| Receita | +valor na conta | obrigatória, do tipo receita |
| Despesa | −valor na conta | obrigatória, do tipo despesa |
| Transferência | −valor na origem e +valor no destino, na mesma transação | proibida |

Estados: `previsto` (sem movimentos; não altera saldo) → `efetivado` (movimentos gerados) → `cancelado` (movimentos removidos, lançamento preservado com data e motivo, imutável). Só `previsto` pode ser excluído fisicamente.

Datas: `data_competencia` (fato; base do resultado mensal), `data_vencimento` (controle), `data_efetivacao` (base do saldo; existe se e só se efetivado).

## 2. Banco (`supabase/migrations/20260902000005_lancamentos.sql`)
| Objeto | Função |
|---|---|
| `lancamentos` | Evento. Constraints: valor > 0; transferência ⇔ sem categoria ⇔ com destino distinto; efetivado ⇔ data_efetivacao; cancelado ⇔ cancelado_em. Guarda a conta planejada (e destino). |
| `movimentos` | Efeito por conta. Valor ≠ 0. Denormaliza `organizacao_id` para RLS e auditoria. |
| `motor_ativo()` + triggers de proteção | **Ninguém grava nas duas tabelas fora do motor**: os triggers exigem a flag de sessão `erp.motor`, ligada só dentro das funções do motor. Clientes têm apenas `SELECT`. |
| `tg_lancamentos_protecao` | Valida conta/destino/categoria (organização, tipo, ativos), tipo imutável, cancelado imutável, exclusão só de previsto. |
| `gerar_movimentos(id)` | Regenera os movimentos a partir do estado do lançamento (idempotente). |
| `criar_lancamento(...)` | Cria previsto ou efetivado (conforme `p_data_efetivacao`). Organização derivada da conta; exige membro. |
| `atualizar_lancamento(...)` | Edição auditada de previsto/efetivado; regenera movimentos. Tipo não muda. |
| `efetivar_lancamento(id, data)` | previsto → efetivado. |
| `cancelar_lancamento(id, motivo)` | qualquer não cancelado → cancelado; remove movimentos (auditados). |
| `excluir_lancamento(id)` | Somente previsto. |
| `vw_saldo_contas` | Conta + `saldo` + nº de movimentos. `security_invoker`: RLS do usuário. |
| `vw_resultado_mensal` | Receitas, despesas e resultado por mês de competência, só efetivados, sem transferências. |
| RLS | `select` por organização nas duas tabelas. Sem policies de escrita (as funções são `security definer` e validam membro via `exigir_membro`). |

Efeito colateral desejado: `conta_possui_movimentos` e `categoria_possui_lancamentos` (Etapas 3 e 4) passam a responder de verdade. Inativar conta com movimentos ou categoria com lançamentos agora é bloqueado em produção.

## 3. App
| Módulo | Conteúdo |
|---|---|
| `modules/lancamentos` | `api.ts` (consulta mensal + 5 mutações via RPC + busca de duplicados), `FormularioLancamento` (tipo em rádio, descrição, valor, data, conta/origem, destino ou categoria agrupada por pai, "Já pago/recebido/realizada" com data de efetivação ou vencimento, observação), `AcoesLancamento` (marcar como pago/recebido, cancelar com motivo, excluir previsto; cancelado é somente leitura), `LancamentosPage` (seletor de mês, filtros de tipo e status, totais efetivados, tabela com cores por tipo e status) |
| `modules/dashboard` | Saldo total (contas ativas), receitas, despesas e resultado do mês, saldo por conta, últimas 8 movimentações efetivadas, seletor de mês |
| `modules/contas` | Lista passa a ler `vw_saldo_contas`: nova coluna **Saldo atual** |
| núcleo | `SeletorMes`, `AreaTexto`, `Distintivo` com tons alerta/info, formatos de mês |

**Aviso de duplicidade** (regra 10 da arquitetura): ao salvar, o app procura lançamento não cancelado com mesma conta, mesmo valor e data ±1 dia; se achar, mostra o aviso e exige "Salvar mesmo assim".

## 4. Decisões técnicas (aprovadas pelo proprietário em 02/09/2026)
1. **Escrita só pelo motor**, com flag de sessão verificada por trigger. Mesmo um bug no app ou um acesso direto à API não consegue criar lançamento sem movimento ou movimento órfão.
2. **Cancelar remove movimentos** em vez de gerar estorno. Mais simples para uso pessoal; a auditoria guarda os movimentos removidos (testado). Estorno contábil pode ser adicionado depois sem alterar o modelo.
3. **Edição de efetivado permitida** e auditada, regenerando movimentos. Alternativa (bloquear e exigir cancelar + recriar) foi descartada por atrito no uso pessoal.
4. **Resultado mensal por competência**, saldo por efetivação. Relatórios futuros por vencimento usam a coluna própria.
5. **Regra mantida por decisão do proprietário**: conta com movimentos não pode ser inativada. Será reavaliada quando houver necessidade real de encerrar uma conta com histórico.

## 5. Testes realizados
| Teste | Resultado |
|---|---|
| SQL T1 receita/despesa/transferência geram movimentos corretos | OK |
| T2 saldo derivado por conta | OK |
| T3 resultado mensal ignora transferência e previstos | OK |
| T4 previsto sem movimento; efetivar gera; efetivar duas vezes falha | OK |
| T5 editar efetivado regenera movimentos (valor e conta) | OK |
| T6 cancelar remove movimentos (auditados), guarda motivo, fica imutável | OK |
| T7 excluir só previsto | OK |
| T8 validações: categoria de outro tipo, transferência com categoria, mesma conta, valor zero, despesa sem categoria | OK |
| T9 cliente não escreve direto em lancamentos/movimentos | OK |
| T10 inativar conta com movimentos e categoria com lançamentos bloqueados | OK |
| T11 RLS: outro usuário não vê nem lança em conta alheia | OK |
| Suítes anteriores (Fundação, Contas, Segurança, Categorias) reexecutadas com o motor real; `verificar_rls` ok nas 7 tabelas; `verificar_lancamentos` 8 de 8 | OK |
| Lint, typecheck, build | OK |
| Interface ponta a ponta: contas com saldo atual → validações → receita, despesa, transferência → duplicidade → previsto → dashboard (saldo ignora previsto, receitas/despesas/resultado, últimas) → efetivar → editar valor → cancelar com motivo → cancelado somente leitura → sem exclusão de efetivado → conta com movimentos não inativa → filtro | 24 de 24 |
| Regressão Categorias 14 de 14 e Contas 11 de 11 | OK |

Rodar tudo localmente: `PGHOST=/tmp PGPORT=5433 PGUSER=postgres supabase/tests/rodar_local.sh`.

## 6. Aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000004_categorias.sql` (se ainda não aplicada) → Run.
2. SQL Editor → `supabase/migrations/20260902000005_lancamentos.sql` → Run.
3. SQL Editor → `supabase/tests/verificar_lancamentos.sql` → esperado `8 de 8 verificações OK`; `verificar_rls.sql` → todas ok.
4. Site: Lançamentos → novo lançamento de cada tipo; Dashboard.
