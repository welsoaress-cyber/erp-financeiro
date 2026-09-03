# Etapa 7 — Faturamento recorrente automático

Status: **validada em produção pelo proprietário (03/09/2026).**

## 1. Como funciona
```
contrato ativo + faturamento automático
   └─ para cada competência devida (mensal / anual / única) ainda não faturada até a data limite
        └─ cria LANÇAMENTO previsto (receita, origem "faturamento", contrato/negócio/pessoa herdados)
             └─ registra em `faturamentos` (contrato, competência) → nunca gera o mesmo mês duas vezes
```
- **Competência mensal**: de "faturar a partir de" até o mês da data limite. **Anual**: uma por ano no mês de aniversário. **Única**: uma vez.
- **Vencimento**: dia do contrato ajustado ao fim do mês (31 → 30, 28/29 em fevereiro). Competência = data de vencimento (o resultado mensal já enxerga o mês certo).
- **Conta e categoria**: conta do contrato, senão a conta padrão do negócio; categoria de receita padrão do negócio. Sem isso, o contrato entra em **pendências** e nada é gerado.
- **Só previstos**: o saldo não muda até você marcar como recebido (ou até a conciliação/pagamento, em etapas futuras).
- **Cancelar** um previsto gerado não faz o mês ser gerado de novo: o registro em `faturamentos` permanece. Para cobrar de novo, lance manualmente com o contrato.
- **Execução**: botão "Gerar faturamento agora" (até hoje; limite de 2 meses à frente) ou agendamento diário às 03:00 (Brasília) via `pg_cron`. Cada execução fica no log com total gerado e pendências.

## 2. Banco
| Migration | Conteúdo |
|---|---|
| `20260902000009_faturamento.sql` | valor `faturamento` no enum de origem; `negocios.conta_padrao_id` e `categoria_receita_id` (validados: mesma organização, categoria de receita, ativos); `contratos.faturamento_automatico`, `faturar_desde` (padrão = início), `conta_id`; tabela `faturamentos` (única por contrato e competência, escrita só pelo motor, auditada); `faturamento_execucoes` (log); funções `data_vencimento_no_mes`, `competencias_pendentes`, `faturar_contrato`, `gerar_faturamento` (por organização), `gerar_faturamento_agora` (RPC, organizações do usuário, limite de 2 meses), `gerar_faturamento_todas` (agendamento); view `vw_faturamentos`; RLS e grants somente leitura. |
| `20260902000010_faturamento_agendado.sql` | `create extension pg_cron` e job `erp-faturamento-diario` (`0 6 * * *` UTC). Migration separada porque depende de extensão do Supabase. |

## 3. App
| Onde | Conteúdo |
|---|---|
| Negócios → formulário | **Conta de recebimento padrão** e **Categoria de receita padrão** |
| Contratos → novo | **Conta de recebimento** (opcional, senão a do negócio); cobranças começam na data de início |
| Contratos → detalhe | Seção **Faturamento recorrente**: ligar/desligar, "faturar a partir de", conta; histórico das competências geradas com status (Previsto / Recebido / Cancelado) |
| Contratos → topo | Botão **Gerar faturamento agora**; painel da última execução (manual ou automática) com total gerado e pendências por contrato |
| Lançamentos | Marca **Automático** nos lançamentos de origem faturamento |

## 4. Decisões técnicas
1. **Tabela de faturamentos separada do lançamento**: a idempotência não depende do status do lançamento. Cancelou por engano, cobra manualmente; não há regeração automática.
2. **Previsto, nunca efetivado**: o sistema não assume que o cliente pagou. Receber é ação sua (ou de integração futura, Mercado Pago).
3. **Competência = vencimento**: simples e coerente com o resultado mensal. Competência "mês de referência do serviço" pode ser adicionada como coluna futura sem quebrar nada.
4. **RPC limitado a 2 meses à frente** para evitar geração acidental em massa; o agendado gera só até hoje.
5. **pg_cron em migration própria**: gratuito no Supabase, mas exige extensão; se o projeto Free estiver pausado por inatividade, o job não roda e o botão cobre o atraso na próxima entrada.
6. Descrição padrão: `Plano · MM/AAAA · contrato #NNN` (editável como qualquer lançamento).

## 5. Testes realizados
| Teste | Resultado |
|---|---|
| SQL T1 pendências (sem conta, sem categoria); categoria de despesa rejeitada | OK |
| T2 mensal jun→set gera 4; vencimentos 30/06, 31/07, 31/08, 30/09 (dia 31 ajustado); origem, herança, conta/categoria, registro, descrição | OK |
| T3 idempotente; cancelado não regera; mês seguinte gera 1; view mostra status; limite de 2 meses | OK |
| T4 suspenso e desligado não geram; "faturar a partir de" limita; anual gera 1 por ano nas datas certas; única gera 1 só; geração distante pelo motor interno | OK |
| T5 cliente não grava em faturamentos; RLS por organização; RPC gera só na própria organização | OK |
| T6 execução agendada cobre todas as organizações | OK |
| Suítes anteriores (9) e `verificar_rls` (14 tabelas); `verificar_faturamento.sql` 7 de 7 | OK |
| Lint, typecheck, build | OK |
| Interface: configuração no negócio, botão desabilitado sem contratos, conta no contrato, pendência sem conta, geração de 3 competências, idempotência, histórico no contrato, marca Automático, vencimento ajustado, descrição, recebimento entra na rentabilidade | 14 de 14 |
| Regressões Contratos 19/19, Negócios 20/20, Lançamentos 24/24 | OK |

## 6. Aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000009_faturamento.sql` → Run.
2. SQL Editor → `supabase/tests/verificar_faturamento.sql` → esperado `7 de 7 verificações OK`.
3. SQL Editor → `supabase/migrations/20260902000010_faturamento_agendado.sql` → Run. Se der erro de extensão, ative **pg_cron** em Database → Extensions e rode de novo.
4. SQL Editor → `supabase/tests/verificar_agendamento.sql` → 1 linha com `active = true`.
5. Site: Negócios → SERVNET → conta e categoria padrão; Contratos → "Gerar faturamento agora"; conferir previstos em Lançamentos.
