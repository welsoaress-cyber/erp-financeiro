# Etapa 40 — Campanha Indique e Ganhe com presente físico

## Regras da campanha (definidas pelo proprietário)
- Indicações ilimitadas; disparo/divulgação manual (WhatsApp e status).
- Indicado que **já é (ou já foi) cliente não conta** — barrado pelo telefone.
- Telefone já indicado não pode ser indicado de novo.
- Presente liberado **depois da instalação** (conversão da indicação).
- O indicante **escolhe o presente** — as opções dependem do plano que o
  indicado fechou: mensalidade até R$ 60 → presente até R$ 30; até R$ 80 →
  R$ 30–50; acima → R$ 50–80. **Sem troca depois da escolha.**
- Entrega em mãos pelo dono em **até 10 dias úteis** da conversão (o painel
  marca "entrega atrasada" quando estoura).
- Se o indicado cancelar depois, nada acontece (custo já coberto).

## Como funciona no sistema (migration 0066)
- `indicacoes` ganhou `convertida_em`, `presente_item_id`, `presente_custo`
  e `presente_entregue_em` — protegidos por trigger (só o motor grava;
  escolha não troca; conversão carimba `convertida_em`).
- **Presentes = itens do Estoque** em categoria cujo nome começa com
  "Brinde" (ex.: "Brindes"); a faixa usa o `valor_custo` (custo médio).
- Funções: `criar_indicacao_admin` (indicação recebida no WhatsApp, com
  dedupe), `escolher_presente_indicacao` (admin registra a escolha),
  `entregar_presente_indicacao` (baixa 1 un. no estoque, origem `brinde`,
  congela o custo), `portal_presentes_indicacao` + `portal_escolher_presente`
  (cliente escolhe no portal, só itens da faixa) e `faixa_presente_indicacao`.
  `portal_indicacoes` passou a devolver a situação do presente.
- `saida_estoque` aceita a origem `brinde`.

## Telas
- **Portal → Indique e ganhe**: indicação convertida mostra "Escolha o seu
  presente" (só os da faixa, com confirmação sem troca) e depois a situação
  ("entrega em até 10 dias úteis" / "entregue em …").
- **Portal do cliente (admin)**: botão **Nova indicação** (WhatsApp), resumo
  da campanha (indicações, convertidas, taxa, entregues, custo dos
  presentes, mensalidade gerada — tudo derivado) e, por linha convertida,
  registrar escolha / marcar **Entregue** / alerta de atraso.

## Para operar a campanha
1. Estoque → categoria **"Brindes"** + itens (jogo, mini game, console) com
   compra registrada (o custo médio define a faixa).
2. Configurações do portal: se o benefício em dinheiro não for usado nesta
   campanha, deixe o benefício por indicação em R$ 0 para não acumular
   desconto + presente.
3. ROI: resumo do painel (custo dos presentes × mensalidade gerada) e BI.
