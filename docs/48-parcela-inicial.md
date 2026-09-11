# Etapa 45 — Parcelamento iniciando de uma parcela específica

## Caso de uso
Migrar para o sistema uma dívida em andamento: comprou em 24×, já pagou a 1ª
fora — lança "24 parcelas, iniciar na 2". Nascem 23 lançamentos numerados
**2/24 … 24/24** (a numeração reflete o contrato, não a quantidade gerada) e
o "Início" é a data da parcela informada.

## Entrega (migration 0071)
- `criar_lancamento` ganha o 18º parâmetro `p_parcela_inicial` (default 1 —
  comportamento antigo preservado); valida 1 ≤ inicial ≤ total.
- `tg_lancamentos_recorrencia` aceita raiz de cadeia com parcela > 1
  (sequência das filhas continua travada em +1).
- Form do lançamento: campo **"Iniciar a partir da parcela"** no bloco
  Parcelamento + resumo (total do contrato, pago fora do sistema, restante).
- `verificar_tudo`: 59 (check 0012 aceita a nova assinatura de 18 args).

## Testes
`parcela_inicial_test.sql`: raiz 2/24 e próxima 3/24; default 1; inicial >
total barrada; iniciar na última não gera próxima.
