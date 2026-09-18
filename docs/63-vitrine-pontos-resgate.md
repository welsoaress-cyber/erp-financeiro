# Etapa 58B: Vitrine de prêmios + resgate de pontos

## Motivo

A 58A criou o motor que concede pontos por pagamento adiantado, mas ainda não dava pra trocar por nada. A 58B fecha o ciclo: catálogo de prêmios físicos e desconto em fatura, os dois pagos com pontos.

## O que foi feito

- **Catálogo de prêmios** (`pontos_premios`, por negócio): nome, foto, item do Estoque (categoria Brindes) e **preço em R$** definido pelo proprietário. O custo em pontos é calculado sozinho: `ceil(valor_reais / 0,22)` — R$ 0,22 por ponto.
- **Desconto em fatura**: sem catálogo — o cliente informa quantos pontos quer converter, à razão de **R$ 0,25 por ponto**, mínimo 4 pontos (R$ 1,00). Aplica na **próxima fatura em aberto** (a de vencimento mais próximo). Se o valor pedido passar do valor da fatura, o desconto é limitado a 100% dela — nesse caso a fatura vira **cortesia** (cancelada com motivo), igual ao padrão já usado no sistema (etapa 52).
- **Resgate de prêmio físico**: cliente escolhe no Portal → debita os pontos na hora (trava, sem troca), fica "aguardando entrega". **Entrega** é sempre confirmada pelo proprietário (Configurações → Programa de pontos) — só aí a baixa de estoque acontece e o custo real (custo médio ponderado) fica registrado pro relatório de ROI.
- **Saldo** (`vw_saldo_pontos`) agora é ganhos (`pontos_pontualidade`) menos resgates (`pontos_resgates`).
- **Portal do cliente** — tela "Meus pontos": saldo, vitrine de prêmios (com botão trocar), formulário de desconto (mostra o valor em R$ em tempo real) e extrato completo (ganhos e resgates).
- **Admin** — Configurações → Programa de pontos: cadastro dos prêmios + lista de resgates aguardando entrega com botão "Entregue".
- **Relatório "Resgates de pontos (ROI)"** na Central de Relatórios: cada resgate, tipo, prêmio, pontos, valor e situação.

## Regras importantes

- Prêmio físico exige item na categoria **Brindes** do Estoque (mesma regra do Indique e Ganhe) — reaproveita o mesmo catálogo de itens, cada programa com seus próprios prêmios cadastrados.
- Sem saldo em estoque → prêmio some da vitrine do portal automaticamente.
- Nunca é possível resgatar sem pontos suficientes — a função valida o saldo antes de debitar.
- Sem aviso de WhatsApp (decisão do proprietário): tudo fica só no portal, passivo.

## Deploy (proprietário)

Aplicar a migration `20260902000102_vitrine_pontos_resgate.sql` pelo SQL Editor. Depois, Configurações → Programa de pontos → cadastrar os prêmios (precisa de itens na categoria Brindes do Estoque com saldo).
