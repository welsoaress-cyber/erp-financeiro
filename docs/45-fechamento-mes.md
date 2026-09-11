# Etapa 42 — Fechamento de mês (trava do realizado)

## Regra
Mês fechado = realizado conferido com o banco. Dentro dele:
- Nenhum lançamento **efetivado** pode ser alterado, cancelado ou excluído.
- Nada novo pode ser efetivado com **data de efetivação** dentro do mês.
- **Cobranças em aberto (previstas) continuam vivas**: podem ser baixadas
  depois (o caixa entra no mês atual) e o faturamento retroativo funciona.
- Reabrir é explícito, com confirmação, e auditado (tabela `auditoria`).
- Só meses já encerrados no calendário podem ser fechados.

## Entrega (migration 0068)
Tabela `fechamentos_mes` (única por organização+competência, sem
insert/update/delete direto para o cliente), funções `fechar_mes`,
`reabrir_mes` e `mes_fechado`, e a trigger `lancamentos_a0_fechamento`
que aplica a trava em qualquer caminho de escrita (inclusive o motor).

## Tela
Financeiro → Lançamentos: ao navegar para um mês passado aparece
**"🔒 Fechar mês"** ao lado do seletor; mês fechado mostra o selo
"🔒 Mês fechado" com o link "reabrir" (ambos com confirmação).

## Testes
`supabase/tests/fechamento_test.sql`: mês corrente não fecha; efetivado de
mês fechado não edita/cancela; baixa atrasada permitida com data em mês
aberto e barrada com data dentro do fechado; reabrir libera.
`verificar_tudo.sql`: 56.
