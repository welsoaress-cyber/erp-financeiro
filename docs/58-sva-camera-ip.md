# SVA — Câmera IP: campanha de upgrade e serviço com mensalidade

> Ideia do proprietário (16/09/2026). **Não implementar sem pedido.** Irmão do
> `docs/57-sva-ponto-adicional.md`: mesmo desenho (comodato + recorrência), produto diferente.

## São DOIS produtos, não um

Misturar os dois é o erro que faz a campanha parecer lucrativa e não ser:

| | O que é | Onde entra na conta |
|---|---|---|
| **Câmera no upgrade** | Brinde/comodato para quem migra ao plano maior | **Custo de aquisição** — sai do bolso hoje para render na mensalidade maior |
| **Instalação + manutenção** | Serviço com mensalidade própria | **Receita** — margem quase 100%, sem fornecedor |

Dá para fazer os dois juntos (câmera de graça no upgrade + mensalidade de manutenção), mas
a conta de cada um tem de fechar separada.

## A campanha: câmera para quem sobe de plano

**Regra:** cliente que migra para o plano maior leva uma câmera IP instalada, em comodato.

**A conta que decide** (faça antes de anunciar):

```
diferença de mensalidade (plano maior − plano atual) × meses de fidelidade
                            deve ser MAIOR que
              custo da câmera + mão de obra da instalação
```

- Sobe R$ 30/mês e a câmera custa R$ 150 → paga em 5 meses. Com fidelidade de 12, sobra.
- Sobe R$ 10/mês → 15 meses só para empatar. **Campanha dá prejuízo**; não faça.

## Regras do produto

- **Comodato, nunca brinde.** A câmera continua sua e volta no encerramento. Sem isso, quem
  cancela no 3º mês leva o equipamento e o prejuízo é integral. O ERP já controla comodato
  com número de série e gera a OS de recolhimento automática.
- **Você NÃO guarda a imagem.** Gravação fica no cartão SD da câmera ou na nuvem do
  fabricante. No momento em que vídeo da casa do cliente passa pelo seu servidor, entra
  responsabilidade de LGPD e um risco que não é do seu negócio.
- **Mensalidade de manutenção separada.** Câmera gera chamado: senha esquecida, trocou o
  Wi-Fi, app parou, mudou de lugar. Sem mensalidade, cada câmera instalada vira suporte
  vitalício de graça.
- **Olho no upload.** Câmera com gravação em nuvem sobe dados 24h. Uma não pesa; cem pesam.
  Vale acompanhar o consumo de upload da OLT depois das primeiras dezenas.

## Teste antes de escalar

Comprar **10 unidades** é o tamanho certo do teste. O número que decide a repetição da
compra não é quantos upgrades fecharam — é **quantos chamados essas 10 geraram em 60 dias**.
Se cada câmera trouxe mais de um chamado por mês, o produto só fecha com mensalidade de
manutenção; se quase não gerou, dá para usar como isca de upgrade sem cobrar nada por ela.

## Como fica no ERP hoje — sem etapa nova

1. Câmeras entram no **Estoque** como item (compra das 10 com pagamento misto, se for o caso).
2. Na entrega: **Estoque → Comodato**, no nome do cliente, com número de série.
3. A despesa da compra fica **vinculada ao contrato** de cada cliente que recebeu → entra no
   payback dele e no relatório *Custo por cliente*.
4. A mensalidade de manutenção: **plano** próprio + **contrato adicional** (mesmo caminho do
   ponto adicional), e o faturamento automático cobra todo mês.
5. O upgrade em si é a troca de plano no contrato existente.

**O que não existe hoje:** marcar a campanha ("recebeu câmera na migração") para medir depois
quantos desses clientes ficaram. Daria para usar centro de custo ou uma observação padrão,
mas o certo seria um campo de campanha no contrato — só vale a pena se a campanha repetir.
