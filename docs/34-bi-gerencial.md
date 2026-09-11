# 34 · BI Gerencial — Etapa 32 (migration `20260902000060_bi_gerencial.sql`)

Tela **Gerencial** (menu próprio) com os indicadores consolidados, calculados **em tempo real** — sem tabelas novas, só a view `vw_bi_mensal_negocio` (negócio × mês, últimos 13 meses):

- novos contratos, cancelamentos, ativos no início/fim do mês
- **churn %** = cancelamentos ÷ ativos no início do mês
- **MRR** no fim do mês (valor mensalizado dos contratos de receita vigentes) e **ticket médio** (MRR ÷ ativos)
- receita **prevista** com vencimento no mês, **recebida** e **inadimplência %** (vencidas em aberto ÷ previstas do mês)

A tela junta: cartões do mês atual (ativos, MRR, ticket, churn, inadimplência, **payback médio** — média do estimado da vw_payback_contrato), tabela dos 13 meses, **desempenho por técnico** (chamados encerrados nos últimos 90 dias: quantidade, tempo médio, nota média, retornos — dados da etapa 29) e **exportação CSV** (separador `;`, com BOM para abrir direto no Excel). Filtro por negócio; churn > 3% e inadimplência > 10% ficam em vermelho. Sem gráficos por decisão de estilo do proprietário.

## Testes

`supabase/tests/bi_test.sql`: churn de 50% no mês do cancelamento (2 ativos no início, 1 encerrado), MRR/ticket após o cancelamento, recebido/previsto do mês corrente, inadimplência com vencida em aberto, 13 meses por negócio. `verificar_tudo.sql`: **48 de 48**.
