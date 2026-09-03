# 23 · Resumo Financeiro do Período (Etapa 15)

Migration `20260902000028_saldo_inicial_mes.sql` — só o saldo inicial precisa de consulta própria (soma de `saldo_inicial` + movimentos anteriores ao mês, por negócio); o resto do resumo é calculado no app a partir dos mesmos lançamentos que o Financeiro já busca.

## Bloco no Dashboard
Substitui a antiga tabela "Resultado por negócio" por um resumo mais completo:

| | Previsto | Realizado | Total |
|---|---|---|---|
| Saldo inicial do mês | — | — | valor |
| Receitas | soma previsto | soma realizado | soma |
| Despesas | soma previsto | soma realizado | soma |
| **Resultado do período** | Receitas − Despesas | Receitas − Despesas | Receitas − Despesas |
| Saldo final estimado do mês | | | saldo inicial + receitas − despesas |

- Respeita o filtro de negócio já existente no Dashboard (todos / pessoal / um negócio).
- Sem filtro e com mais de um negócio, "Detalhar por negócio" expande uma tabela com saldo inicial e resultado realizado por negócio.
- Previsto/Realizado seguem a mesma definição do módulo Financeiro (por `data_competencia`, no mês selecionado).

## Teste
`supabase/tests/saldo_inicial_test.sql` (saldo antes/depois do mês, por negócio, conta aberta durante o mês não conta, conta inativa não conta).
