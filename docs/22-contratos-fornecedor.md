# 22 · Contratos de fornecedor e lançamento automático (Etapa 14)

Migration `20260902000027_contratos_despesa_automatico.sql`.

## O que muda
- Contrato ganha `tipo_financeiro`: **Cliente (receita)** — como já era — ou **Fornecedor (despesa)**.
- **Ao salvar o contrato, o sistema já gera sozinho o primeiro lançamento previsto** (receita em Contas a Receber, ou despesa em Contas a Pagar) — não precisa mais clicar em "Gerar faturamento agora" depois. Competências atrasadas (contrato retroativo) e os meses seguintes continuam a cargo de "Gerar faturamento agora" e do cron diário, como já era.
- O vínculo automático da pessoa com o negócio passa a respeitar o tipo: **cliente** para receita, **fornecedor** para despesa (antes era sempre "cliente").

## Negócio: conta e categorias
`negocios` ganhou `categoria_despesa_id` (mesma regra de `categoria_receita_id`: precisa ser categoria do tipo certo, e pode ficar inativa vindo de antes). A conta é a mesma (`conta_padrao_id` já servia para recebimento; agora também serve para pagamento) — pode ser sobrescrita por contrato como já acontecia.

Sem a categoria configurada, o contrato é criado normalmente mas sem lançamento automático (mensagem de aviso no log do banco); basta configurar o negócio e clicar em "Gerar faturamento agora" depois.

## App
- Contratos: seletor "Cliente (receita)" / "Fornecedor (despesa)" no formulário; rótulo da pessoa muda ("Cliente"/"Fornecedor"); lista mostra o tipo abaixo do nome.
- Negócios: novo campo "Categoria de despesa padrão".

## Teste
`supabase/tests/contratos_despesa_test.sql`.
