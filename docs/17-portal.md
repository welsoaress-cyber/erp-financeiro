# Etapa 11 — Portal do Cliente

Status: **implementada e testada localmente (03/09/2026); aguardando aplicação da migration 0023 em produção e validação do proprietário.**

## 1. Objetivo
Área web onde o cliente, com login próprio, vê só os seus dados: situação financeira, faturas (com PDF), próximas cobranças, pagamentos, plano, promoções e o programa Indique e Ganhe. Nada do sistema administrativo é acessível a ele.

## 2. Como funciona
```
Cliente cria acesso (/portal/cadastro: e-mail + senha; metadata portal=true → NÃO ganha organização)
  └─ confirma CPF/CNPJ + telefone (/portal/vincular → portal_vincular) → portal_acessos (login ↔ pessoa) + código de indicação
       └─ tudo o que o portal mostra vem de funções portal_* (security definer) filtradas pela pessoa do login
            faturas = cobranças de contrato (lançamentos de receita com contrato_id) · próximas = competências pendentes do faturamento
            pagamentos = cobranças efetivadas · plano = contratos · promoções vigentes do negócio/plano · indicações
Indique e Ganhe: link único /portal/indicacao/<código> (página pública) ou indicação direta no portal
  └─ administrador converte (indicado virou pessoa) → desconto (portal_config.beneficio_indicacao) na PRÓXIMA cobrança do indicador
       └─ faturar_contrato aplica descontos_contrato pendentes e registra "Desconto aplicado" na observação
```
- **Isolamento:** o cliente não é membro de organização, então nenhuma policy das tabelas do ERP o alcança. O app redireciona login de cliente para `/portal` e login de administrador para o ERP. Teste SQL comprova que o cliente lê zero linhas de `lancamentos`, `pessoas` e `contratos`.
- **Vínculo seguro:** CPF/CNPJ + telefone cadastrado (últimos 8 dígitos) precisam bater; uma pessoa só tem um login; login de administrador não vincula.
- **Boleto/PDF:** página pronta para impressão (Salvar como PDF no navegador) com Pix e instruções do negócio. Não é boleto bancário registrado (sem gateway, conforme decisão).
- **Recuperação de senha:** e-mail do Supabase Auth (gratuito) com retorno em `/portal/nova-senha`.
- **Não implementado agora:** login por CPF (o Supabase autentica por e-mail; expor e-mail a partir do CPF vazaria dados) e login por código no WhatsApp (opcional; depende de custo e do provedor).

## 3. Banco (migration `20260902000023_portal_cliente.sql`)
- `portal_config` (por negócio): ativo, logo, cor, texto promocional, chave Pix, instruções de pagamento, benefício por indicação.
- `portal_acessos`: login ↔ pessoa, código de indicação (8 caracteres, único).
- `promocoes`: por negócio, opcionalmente restrita a um plano, com vigência.
- `indicacoes`: indicador, indicado (nome/telefone; pessoa quando convertida), status, benefício.
- `descontos_contrato`: descontos pendentes aplicados pelo faturamento.
- `tg_novo_usuario` ignora usuários com `portal=true`. `faturar_contrato` passa a aplicar descontos.
- Funções: `portal_vincular`, `portal_resumo`, `portal_faturas`, `portal_proximas_faturas`, `portal_pagamentos`, `portal_contratos`, `portal_promocoes`, `portal_indicacoes`, `portal_indicar` (authenticated); `portal_info_indicacao`, `portal_indicacao_publica` (anon, com limite diário); `converter_indicacao` (administrador). View `vw_portal_acessos`.

## 4. Interface
- **Cliente** (`/portal`): entrar, criar acesso, recuperar senha, confirmar cadastro, Início, Faturas (filtro, PDF, próximas), Pagamentos, Meu plano, Indique e ganhe (link, copiar, WhatsApp, indicar, histórico), Promoções. Página pública `/portal/indicacao/<código>`.
- **Administrador** (menu Portal do cliente): configuração por negócio, promoções, indicações (converter / cancelar), lista de acessos.

## 5. Testes
- `supabase/tests/portal_test.sql`: usuário portal sem organização, vínculo (telefone errado, CPF inexistente, idempotência, segunda conta, administrador), resumo/faturas/situações/próximas/pagamentos/contratos/promoções, isolamento (0 linhas do ERP), indicação logada e pública (anon), conversão com desconto na próxima fatura e consumo do desconto.
- `supabase/tests/verificar_portal.sql`: 6 verificações. `verificar_tudo.sql` passa a 17.
- e2e: fluxo completo administrador → cliente → link público → conversão → fatura com desconto.

## 6. Como aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000023_portal_cliente.sql`.
2. `supabase/tests/verificar_portal.sql` → 6 de 6; `verificar_tudo.sql` → 17 de 17.
3. Painel Supabase → Authentication → URL Configuration: adicionar `https://erp-financeiro.welsoaress.workers.dev/portal/nova-senha` aos Redirect URLs.
4. No ERP: menu Portal do cliente → Ativar portal (Pix, benefício). Depois, com um cliente de teste: `/portal/cadastro`.
