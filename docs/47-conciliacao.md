# Etapa 44 — Conciliação bancária

## Regra
Cada movimento de conta pode ser marcado como "conferido no extrato"
(`movimentos.conciliado_em`, reversível, só pela função
`conciliar_movimentos` — sem grant de update na tabela). A tela
Financeiro → **Conciliação** mostra, por conta e mês: total de movimentos,
conferidos × pendentes (com somas), lista com checkbox por movimento e
"Conferir todos". Mês 100% conferido + saldo batendo = fechar o mês
(etapa 42) com segurança.

## Entrega
Migration 0070 (coluna + função definer com flag do motor), teste
`conciliacao_test.sql` (marca/desfaz, update direto barrado, RLS),
página `ConciliacaoPage` como 5ª aba do Financeiro. `verificar_tudo`: 58.

## 0138-0142 · correções e melhorias encontradas em produção
Bugs: a tela montava a data de início da consulta errado (`mes` já vinha como "AAAA-MM-01", o código acrescentava mais um "-01" por cima, virando data inválida) — não achava NENHUM movimento, mesmo com lançamentos reais na conta/mês. O mesmo descompasso de formato fazia o mês selecionado nunca ser lembrado ao trocar de aba (`usePeriodo`). Os dois corrigidos em 0138-0140 (fix de app, sem migration).

Melhorias pedidas pelo proprietário ao usar a tela de verdade:
- **Nome do cliente** aparece junto da descrição (antes só tinha "Mensal/35 · 09/2026 · contrato #001", sem saber de quem era).
- **Filtro por dia**: a lista do mês inteiro ficava "bagunçada" — select novo filtra pra um dia só, na mesma barra de filtros.
- **"Ajustar baixa" (0142)**: pagamento conferido numa conta errada (ex.: marcado como recebido no Mercado Pago, mas caiu na Caixa) — botão "Ajustar baixa" ao lado de cada movimento abre um select de contas e move o lançamento (já efetivado) pra conta certa, sem reabrir a edição completa do lançamento. Função nova `corrigir_conta_lancamento` (motor, recalcula `movimentos`); não serve pra transferência (duas contas em jogo — edita pelo fluxo normal).
