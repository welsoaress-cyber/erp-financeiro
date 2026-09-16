# SVA — Ponto adicional / repetidor com mensalidade

> Ideia do proprietário (16/09/2026). **Não implementar sem pedido.** Este doc é a
> anotação do produto: como vender, como precificar e como já cabe no ERP de hoje.

## A ideia

Hoje o normal no mercado é cobrar a instalação do ponto adicional **uma vez** (taxa de
R$ 100–200) e acabou. Vira receita de uma vez só, some do fluxo no mês seguinte, e o
equipamento fica na casa do cliente sem gerar nada.

A virada: **cobrar mensalidade pelo ponto adicional**, em vez da taxa. O cliente paga
menos para entrar (barreira baixa, converte muito mais) e você ganha receita recorrente
pelo resto do contrato — com o mesmo equipamento que já ia instalar de qualquer jeito.

## Por que funciona no bairro

- A objeção do cliente é **o valor de entrada**, não o valor mensal. "R$ 150 agora" trava;
  "R$ 20 por mês" não.
- Casa de laje, dois andares, fundos e quintal é o padrão da periferia — reclamação de
  "não pega no fundo" é o chamado técnico nº 1 depois de queda de sinal.
- Resolve reclamação de cobertura **cobrando por isso**, em vez de mandar técnico de graça.
- Aumenta a fidelidade: quem tem 2 pontos configurados não troca de provedor por R$ 10.

## Como montar o produto

**O que entra na mensalidade:**
- Equipamento em **comodato** (repetidor/mesh) — continua seu, volta no encerramento.
- Instalação e configuração inclusas.
- Troca sem custo se der defeito.
- Suporte e reconfiguração quando o cliente mudar a senha ou o móvel de lugar.

**O que não entra:** perda, roubo ou dano por mau uso — aí é cobrado à parte
(mesma regra do comodato que o ERP já tem).

## Como precificar

Conta simples, sem chute:

1. Custo do repetidor (custo médio do item no Estoque) + mão de obra da instalação.
2. Divida por **12 meses**: esse é o piso da mensalidade só para pagar o equipamento em 1 ano.
3. A mensalidade de venda deve ficar **acima** disso, com folga para a troca por defeito.
4. Do 13º mês em diante é margem quase pura — o equipamento já se pagou.

O ERP calcula o payback disso sozinho se o repetidor for lançado com **Contrato** = o do
cliente (é a regra "comprou para um cliente, vincula ao contrato").

## Como fica no ERP hoje — sem etapa nova

Já dá para operar assim, sem escrever uma linha de código:

1. **Plano** novo em Contratos → Planos do negócio: "Ponto adicional" com o valor mensal.
2. **Contrato adicional** para a mesma pessoa, com esse plano. O faturamento automático passa
   a gerar a cobrança todo mês junto com a internet.
3. O repetidor entra em **Estoque → Comodato**, no nome do cliente e com número de série —
   o ERP já gera a OS de recolhimento quando o contrato for encerrado.
4. A despesa da compra do repetidor fica **vinculada ao contrato do cliente**: entra no
   payback e no relatório *Custo por cliente*.

**O que ainda não existe:** agrupar "internet + ponto adicional" numa fatura só na visão do
cliente (hoje são duas linhas). Se virar padrão de venda, vale uma etapa para isso.

## Texto para o site / material de venda

> **Wi-Fi em toda a casa, sem pagar instalação.**
> O sinal não chega no quarto dos fundos? A gente instala um ponto adicional na sua casa por
> [R$ X] por mês — sem taxa de instalação, sem comprar equipamento. Se der problema, a gente
> troca. Se você sair, é só devolver.
> - Instalação e configuração inclusas
> - Equipamento da [PROVEDOR], com troca garantida
> - Cancele quando quiser

Três perguntas que o cliente vai fazer, e as respostas:
- *"O equipamento fica meu?"* Não — é nosso, em comodato. Por isso você não paga por ele.
- *"E se eu cancelar a internet?"* Devolve o aparelho, sem multa pelo ponto adicional.
- *"Quantos posso ter?"* Quantos a casa precisar; cada um tem sua mensalidade.

## Riscos a vigiar

- **Equipamento parado na rua:** se o cliente cancelar e não devolver, virou prejuízo. A OS
  de recolhimento automática do ERP cobre isso, mas alguém tem que executá-la.
- **Preço baixo demais:** mensalidade que não paga o equipamento em ~12 meses transforma
  crescimento em buraco de caixa. Faça a conta acima antes de anunciar.
- **Virar suporte de graça:** deixe claro que a mensalidade cobre o ponto adicional, não
  reconfiguração da casa inteira toda vez que o cliente troca o celular.
