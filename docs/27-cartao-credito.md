# 27 · Cartão de crédito (Etapa 25)

Migrations `20260902000038_cartao_credito.sql` e `20260902000039_cartoes_agendado.sql` (pg_cron diário 05:30 UTC).

## Modelo (sem sistema paralelo)
- **O cartão é uma conta** do novo tipo `credito`: `saldo_inicial` = limite total; o saldo derivado (vw_saldo_contas) = **limite disponível**.
- **Compra à vista** = despesa efetivada na conta-cartão (consome limite na hora).
- **Parcelado** = motor de parcelamento existente (parcelas previstas; **viram efetivadas no fechamento** da fatura em que caem — só aí consomem limite).
- **Pagamento** = transferência real (motor) de outra conta para a conta-cartão; **restaura o limite exatamente no valor pago**. Parcial permitido.
- Sem juros/multa/rotativo nesta etapa. Validação de limite é da tela (o banco não bloqueia compra acima do limite neste MVP).

## Banco
- `cartoes_config` (conta_id único, dia_fechamento/dia_vencimento 1–28, limite_total) — editável pelo usuário; trigger exige conta tipo `credito` da mesma organização.
- `faturas` (período, vencimento, valor_total, valor_pago, status `aberta|paga|vencida`) e `fatura_itens` (fatura ↔ lançamento; nº/total de parcela já vivem em `lancamentos`) — só o motor grava (`erp.motor`).
- Funções: `fechar_fatura_cartao` (interna, idempotente por conta+período), `fechar_faturas_cartoes` (cron), `fechar_faturas_agora` e `pagar_fatura` (authenticated). Vencimento no mesmo mês do fechamento quando o dia é maior; senão mês seguinte.

## Tela
`/cartoes`: cartões (disponível, limite, dias), Configurar cartão (conta crédito + dias + limite), Faturas (período, total, status, Pagar fatura com conta origem/valor/data — parcial ok), detalhe com os lançamentos da fatura, botão "Fechar faturas agora". Conta de crédito é criada em Contas (tipo novo "Cartão de crédito", saldo inicial = limite).

## Testes
`supabase/tests/cartoes_test.sql` (config só crédito; à vista consome/parcela prevista não; fechamento consolida + efetiva parcelas + idempotente; pagamento parcial/total restaura saldo; vencida marcada). `verificar_tudo.sql`: 31 de 31. E2E: sem infra Playwright no checkout (docs/25).
