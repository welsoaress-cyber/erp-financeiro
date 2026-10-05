# 70 · Dashboard Operacional (redesenho)

Migration `20260902000125_dashboard_agenda.sql`. Módulo `app/src/modules/dashboard`. Mockup aprovado pelo proprietário antes da implementação (Artifact "Design").

## Pedido do proprietário
Dashboard limpo, orientado a ação, sem poluição: "informação sem ação" fora, negócios nunca misturados, previsto × realizado sempre distinto, sem cards vazios/redundantes.

## As 5 camadas (nessa ordem, na página `/`)
1. **Resumo** (4 cards): Saldo total · A receber 30 dias · A pagar 30 dias · Resultado do mês (projetado — realizado + previsto do mês selecionado).
2. **Agenda financeira**: Hoje / Próximos 7 dias / Próximos 30 dias / Acima de 30 dias — cada linha com A Pagar | A Receber | Saldo Projetado, clicável (leva a Lançamentos). Faixas **mutuamente exclusivas** (não cumulativas), só `status = 'previsto'` com vencimento a partir de hoje — vencidos já têm bloco próprio em Pendências. View nova: `vw_dashboard_agenda`.
3. **Pendências**: Contas a pagar vencidas · Contas a receber vencidas · Clientes bloqueados · Compras aguardando recebimento · Avisos pendentes (WhatsApp) · Estoque em alerta (item adicional, fora do pedido original — zerado/abaixo do mínimo já existia como alerta solto no dashboard antigo, virou card de pendência em vez de desaparecer). Cada card é um link direto pro módulo já filtrado.
4. **Visão por negócio**: um bloco por negócio (nunca somado entre negócios, conforme pedido) — barra previsto × realizado de receitas e de despesas, resultado do negócio. Reaproveita `vw_resultado_mensal_negocio` (realizado) + lançamentos previstos do mês + projeção de contratos (meses ainda não faturados, derivada, nunca pré-gerada) agrupados por negócio no navegador.
5. **Movimentações recentes**: últimas efetivadas — data, descrição, valor, conta, status.

Abaixo das 5 camadas, dois blocos recolhidos por padrão (já existiam, mantidos por terem informação que as camadas acima não cobrem): **Resumo financeiro do mês** (previsto × realizado × natureza — doc 23) e **Saldo por conta**.

## O que saiu do dashboard antigo
`AlertaBloqueados`, `StatusPessoas`, `SaudeAvisos`, `AlertasEstoque` e `RelatorioCobranca` (anéis de cobrança por período) foram removidos — o conteúdo deles está coberto pela camada Pendências (clientes bloqueados, avisos, estoque) ou pela Agenda financeira (cobrança prevista por período). Se o proprietário sentir falta de algum anel/detalhe específico de "Cobrança do período" (confirmadas × a receber × inadimplentes com filtro dia/semana/mês/acumulado), dá pra trazer de volta como card à parte — não foi pedido no redesenho, por isso ficou fora.

## Ocultar valores (0126)
Botão no cabeçalho (ícone de olho) troca todo valor em dinheiro exibido no Dashboard por "••••••" — pedido do proprietário pra abrir a tela em público sem expor números. Estado em `localStorage` (`erp.dash.ocultarValores`), só nesta página. Implementado com `formatarMoedaOuOculto(valor, oculto)` (`core/formatos`) propagado por prop a cada subcomponente — sem SQL, sem migration.

## SQL novo
`vw_dashboard_agenda` (`security_invoker`): `organizacao_id, negocio_id, tipo, bucket, valor` — um `select` sobre `lancamentos` com `case` de faixa de vencimento; `status = 'previsto'`, `tipo in ('receita','despesa')`, `data_vencimento >= current_date`. Sem RLS própria: herda a de `lancamentos`.

## Teste
`supabase/tests/dashboard_agenda_test.sql` — vencida não aparece, hoje/7dias/30dias/mais30 somam certo por tipo, efetivado e cancelado não entram.

## Limite assumido (avisar se incomodar)
A Agenda financeira usa só o que já está lançado como previsto — não estica a projeção de contratos (que hoje só cobre o mês selecionado) pros 30 dias seguintes. Na prática, como o faturamento automático já gera a fatura com antecedência, a janela de 30 dias deve estar bem coberta; "Acima de 30 dias" pode subestimar contratos cujo próximo mês ainda não foi faturado. Avisar se os números dessa faixa parecerem baixos.
