# 53 · Contrato cortesia (Etapa 52)

Migration `20260902000078_contrato_cortesia.sql`. Teste `supabase/tests/cortesia_test.sql`.

## Por quê
Alguns clientes não pagam (o próprio proprietário, parceiros). Contrato com valor 0 caía em toda execução do faturamento como pendência "Contrato com valor zero" — ruído, não erro.

## Banco
- `contratos.cortesia boolean not null default false`, check `not cortesia or valor = 0`.
- `faturar_contrato`: contrato cortesia **retorna sem pendência e sem lançamento** (o motor não aceita lançamento de valor 0 e cortesia não é receita). Valor 0 **sem** o flag continua pendência (é erro de cadastro).
- `importar_clientes`: aceita `cortesia: true` por linha → valor 0 + flag; plano novo criado por linha cortesia nasce com valor 0 (ajuste em Planos) — plano existente mantém o valor de tabela.
- Backfill: contratos que já estavam com valor 0 viram cortesia (único significado possível).

## App
- Contratos → Novo / detalhe: caixa **Cortesia (sem cobrança)** (só receita); valor trava em 0.
- Lista: coluna Valor mostra o distintivo **Cortesia**.
- Importar CSV: caixa Cortesia por linha na prévia (etapa anterior) agora grava o flag.

## Efeitos
- Cortesia não entra no Contas a receber, notificações, bloqueio nem Pix. MRR/ticket (Gerencial) contam valor 0 — cliente ativo sem receita.
- Portal do cliente cortesia: "Nenhuma fatura em aberto".
