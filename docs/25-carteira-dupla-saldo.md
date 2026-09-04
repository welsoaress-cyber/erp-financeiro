# Etapa 17 — Carteira com dois saldos (dinheiro e crédito)

Status: **entregue, aguardando validação do proprietário (não aplicado em produção ainda).**

## 1. Objetivo
A carteira de ativação de apps (Etapa 9) operava em **um único modo** por negócio (dinheiro OU crédito, com taxa de conversão fixa). Na prática o negócio real:
- Paga sempre por **PIX** ao dono da plataforma, que credita **dinheiro (R$)** ou **créditos**, sem taxa fixa (varia por negociação).
- Tem **172 apps** disponíveis, cada um com preço que também varia — não é um custo fixo cadastrável.

Este pacote muda a carteira para manter **os dois saldos ao mesmo tempo** (dinheiro e crédito), e faz cada recarga e cada ativação informarem manualmente **a forma de pagamento e o valor**, sem taxa de conversão automática.

## 2. O que muda em relação à Etapa 9
| Antes (0013) | Agora (0030) |
|---|---|
| `negocios.tipo_saldo` (dinheiro OU crédito) + `taxa_conversao` | `negocios.usa_carteira` (liga/desliga o módulo Apps) |
| `carteira.saldo` (um valor) | `carteira.saldo_dinheiro` + `carteira.saldo_credito` (dois valores independentes) |
| `apps_catalogo.custo` (preço fixo por app) | sem custo cadastrado — cada ativação informa o valor pago |
| `recarregar_carteira(negócio, valor_reais, conta, ...)` — unidades calculadas pela taxa | `recarregar_carteira(negócio, forma_pagamento, valor_reais, unidades, conta, ...)` — PIX sempre em R$; unidades creditadas informadas à mão quando é crédito |
| `ativar_app(negócio, cliente, app, ...)` — custo vinha do catálogo | `ativar_app(negócio, cliente, app, forma_pagamento, valor, ...)` — valor informado na hora |

## 3. Regras
- Recarga sempre registra o **PIX pago** (`valor_reais`); se a forma é crédito, também registra quantos **créditos** a plataforma creditou — dois números independentes, sem taxa fixa.
- Ativação em **dinheiro**: debita `saldo_dinheiro` e gera a **despesa do consumo** (R$) na conta da carteira, vinculada ao contrato/cliente — igual à Etapa 9.
- Ativação em **crédito**: debita `saldo_credito`; **não gera despesa** (o custo em R$ já foi reconhecido na recarga que trouxe esses créditos — evita contar duas vezes sem uma taxa fixa para converter).
- Saldo nunca negativo em nenhum dos dois; verificação explícita por forma de pagamento ("Saldo insuficiente (credito): disponível X, necessário Y").
- Transações da carteira continuam imutáveis (só o motor insere; sem update/delete).
- Catálogo de apps: sem preço fixo. Criar app só pede nome + anuidade cobrada do cliente (plano anual).

## 4. Interface
- **Negócios → editar**: campo "Saldo para ativação de apps" vira um checkbox simples "Usa carteira para ativação de apps".
- **Apps → painel**: dois indicadores de saldo (dinheiro e crédito), cada um com total de recargas/consumo daquela forma.
- **Recarregar**: escolhe forma de pagamento; sempre pede o valor do PIX; se crédito, pede também quantos créditos entraram.
- **Ativar app**: escolhe forma de pagamento (dinheiro/crédito) e digita o valor consumido na hora — sem custo pré-cadastrado.
- **Contratos de app**: nova coluna "Pago com" (forma + valor) em cada ativação, para controle de lucro por contrato.

## 5. Banco (migration `20260902000030_carteira_dupla_saldo.sql`)
Altera `negocios` (troca `tipo_saldo`/`taxa_conversao` por `usa_carteira`), `carteira` (troca `saldo` por `saldo_dinheiro`/`saldo_credito`), `apps_catalogo` (remove `custo`), `transacoes_carteira` (nova coluna `forma_pagamento`; `valor_reais` passa a ser opcional). Recria `tg_transacoes_carteira_saldo`, `configurar_carteira`, `criar_app`, `recarregar_carteira`, `ativar_app`, `vw_carteira_resumo`, `vw_contratos_app`. RLS e grants iguais à Etapa 9 (nada para `anon`, sem grant de update/delete além do já existente em `apps_catalogo`).

## 6. Testes
- `supabase/tests/apps_saldo_test.sql` (reescrito para o novo esquema): configuração, catálogo sem custo, fluxo dinheiro (recarga → transferência; ativação → despesa vinculada), fluxo crédito (recarga com PIX + créditos informados manualmente; ativação sem despesa), imutabilidade, saldo insuficiente por forma, situação vencido, `anon` negado.
- `supabase/tests/verificar_apps_saldo.sql`: 7 de 7.
- `supabase/tests/verificar_tudo.sql`: 23 de 23 (linha da 0013 trocada pela verificação da 0030).
- `supabase/tests/rodar_local.sh` atualizado para aplicar a 0030 na posição certa no cenário de produção (logo após a 0013).
- Suíte completa rodada localmente (Postgres 16): todas as suítes OK, produção 23 de 23.
- **e2e**: não há infraestrutura Playwright neste checkout (nenhum spec/mock encontrado); não foi possível rodar/gerar e2e nesta etapa. Sinalizo para não perder o item.

## 7. Como aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000030_carteira_dupla_saldo.sql`.
2. `supabase/tests/verificar_apps_saldo.sql` → esperado **7 de 7**.
3. `supabase/tests/verificar_tudo.sql` → esperado **23 de 23**.
4. Deploy (push em `main`). Depois: em cada app do catálogo já existente, nada a fazer (custo antigo é descartado); nas próximas recargas e ativações, informar forma de pagamento e valor na hora.
