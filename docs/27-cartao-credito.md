# 27 · Cartão de crédito (Etapa 25)

Migrations `20260902000038_cartao_credito.sql` e `20260902000039_cartoes_agendado.sql` (pg_cron diário 05:30 UTC).

## Modelo (sem sistema paralelo)
- **O cartão é uma conta** do novo tipo `credito`. ~~saldo_inicial = limite total~~ (0087: não sincroniza mais — ver seção Correção 0087). O **limite disponível** de verdade vem de `vw_cartoes_limite.disponivel` (limite − uso efetivado − comprometido em parcelas futuras).
- **Compra à vista** = despesa efetivada na conta-cartão (consome limite na hora).
- **Parcelado** = motor de parcelamento existente (parcelas previstas; **viram efetivadas no fechamento** da fatura em que caem — só aí consomem limite).
- **Pagamento** = transferência real (motor) de outra conta para a conta-cartão; **restaura o limite exatamente no valor pago**. Parcial permitido.
- Sem juros/multa/rotativo nesta etapa. Validação de limite é da tela (o banco não bloqueia compra acima do limite neste MVP).

## Banco
- `cartoes_config` (conta_id único, dia_fechamento/dia_vencimento 1–28, limite_total) — editável pelo usuário; trigger exige conta tipo `credito` da mesma organização.
- `faturas` (período, vencimento, valor_total, valor_pago, status `aberta|paga|vencida`) e `fatura_itens` (fatura ↔ lançamento; nº/total de parcela já vivem em `lancamentos`) — só o motor grava (`erp.motor`).
- Funções: `fechar_fatura_cartao` (interna, idempotente por conta+período), `fechar_faturas_cartoes` (cron), `fechar_faturas_agora` e `pagar_fatura` (authenticated). Vencimento no mesmo mês do fechamento quando o dia é maior; senão mês seguinte.

## Tela
`/cartoes`: cartões (disponível, limite, comprometido, dias), Configurar cartão (conta crédito + dias + limite), Faturas (período, total, status, Pagar fatura com conta origem/valor/data — parcial ok), detalhe com os lançamentos da fatura, botão "Fechar faturas agora" (atalho manual — o fechamento roda sozinho todo dia). Conta de crédito é criada em Contas (tipo novo "Cartão de crédito").

## Testes
`supabase/tests/cartoes_test.sql` (config só crédito; à vista consome/parcela prevista não; fechamento consolida + efetiva parcelas + idempotente; pagamento parcial/total restaura saldo; vencida marcada). `verificar_tudo.sql`: 31 de 31. E2E: sem infra Playwright no checkout (docs/25).

## Correção 0087 — dia útil, limite comprometido, casamento de fatura

- **Bug corrigido:** `fechar_fatura_cartao` comparava `data_vencimento` das parcelas contra o dia de FECHAMENTO (`v_fech`) — mas `data_vencimento` é o vencimento real da fatura (ex.: 25), sempre maior que o fechamento (ex.: 16); a condição nunca batia, e nenhuma parcela fechava automaticamente. Passa a comparar por **igualdade** com o vencimento da fatura (`v_venc`), o mesmo valor que o app grava em cada parcela via `vencimentoFatura()` (front, `app/src/modules/cartoes/tipos.ts`).
- **Dia útil:** `ajustar_dia_util()` antecipa sábado/domingo para a sexta anterior — sem tabela de feriados (não há fonte gratuita confiável). Aplicado só na data de vencimento **da fatura** (`faturas.data_vencimento`), nunca na chave de casamento das parcelas (`v_venc` cru) — parcelas futuras são pré-geradas por `projetar_lancamento` (recorrência genérica, "+1 mês" sem noção de fim de semana); se a chave de casamento fosse ajustada, uma parcela caindo num domingo nunca bateria e ficaria "previsto" para sempre.
- **Limite comprometido:** `vw_cartoes_limite` (config_id, conta_id, limite_total, uso_efetivado, comprometido, disponivel) — `disponivel = limite_total + uso_efetivado (soma de movimentos, negativo quando há débito líquido) − comprometido (despesas ainda previstas)`. Não depende de `conta.saldo_inicial`: a trigger `contas_protecao` trava `saldo_inicial` assim que a conta tem qualquer movimento, e um cartão configurado quase sempre já tem — sincronizar `saldo_inicial = limite_total` bateria nessa trava. `/cartoes` lê `disponivel`/`comprometido` da view em vez de `conta.saldo`.
- Testes: `cartoes_test.sql` reescrito com T2b (comprometido no disponível) e T6 (ajustar_dia_util sábado/domingo/dia útil); `verificar_tudo.sql`: 74 de 74.
