# Etapa 38 — Compra de estoque a partir de print (OCR no navegador)

## O que entrega
Botão **"📷 Importar de print"** dentro de Estoque → Nova compra: o
administrador cola (Ctrl+V), arrasta ou escolhe o print do pedido (Shopee,
Mercado Livre, e-mail de confirmação) e o sistema pré-preenche descrição,
quantidade e valor total. Nada é gravado sem revisão: o fluxo continua o da
Nova compra (item, conta, pagamento misto, motor financeiro).

## Como funciona (custo zero)
- OCR 100% no navegador com **Tesseract.js** (MIT, dependência npm,
  `import()` dinâmico — só baixa quando o botão é usado; o idioma `por` vem
  de CDN na primeira leitura).
- Heurística em `ImportarPrint.tsx` (`extrairDadosPedido`):
  - **Total**: linha com "Total (do pedido)" que não seja subtotal/frete/
    desconto; senão o maior R$ positivo do print (ignora linhas `-R$`).
  - **Quantidade**: padrão `x1`, `x2`…
  - **Descrição**: a linha de texto mais longa fora de rótulos conhecidos
    (endereço, pagamento, frete, loja, moedas…), sem selos ("Sob encomenda").
- Print de tela funciona bem; foto de câmera pode falhar — a mensagem de
  erro orienta preencher manualmente.

## Limites do MVP
- Um produto por print (a 1ª linha de item recebe quantidade/valor); pedidos
  com vários produtos: importar preenche o total e a descrição, e as demais
  linhas são adicionadas à mão.
- Sem migration: etapa somente de app.
