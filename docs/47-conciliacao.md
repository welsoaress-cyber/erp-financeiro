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
