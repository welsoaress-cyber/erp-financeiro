# Etapa 9 — Saldo para ativação de apps (dinheiro ou créditos)

Status: **migration 0013 aplicada em produção (03/09/2026, após a correção 0014/0015); aguardando validação do proprietário.**

## 1. Objetivo
Um negócio (ex.: "Ativação de App") mantém uma **carteira** de saldo, em **dinheiro (R$)** ou **créditos**, usada para ativar apps para clientes. Cada ativação consome saldo e abre um **contrato anual** (anuidade) com o cliente. Tudo se integra ao que já existe; nada é duplicado.

## 2. Integrações (o que é reutilizado)
| Módulo | Uso |
|---|---|
| Negócios | Dono da carteira. Novas colunas `tipo_saldo` (dinheiro/credito) e `taxa_conversao` (créditos por R$ 1,00). Conta e categoria de receita padrão do negócio faturam a anuidade. |
| Pessoas | Cliente da ativação = pessoa existente. Vínculo "cliente" criado pelo contrato. |
| Planos | Cada app **é um plano anual** do negócio (preço da anuidade). `apps_catalogo.plano_id` aponta para ele; nome/ativo ficam sincronizados. |
| Contratos | Ativação = contrato anual do plano do app, com faturamento automático (renova a anuidade no ano seguinte). |
| Lançamentos | Recarga = **transferência** efetivada (conta de origem → conta da carteira). Anuidade = **receita prevista** gerada pelo motor de faturamento (Etapa 7). Consumo = **despesa efetivada** na conta da carteira, vinculada ao contrato e à pessoa (rentabilidade por contrato funciona). |
| Contas | `carteira.conta_id` = conta onde o dinheiro da carteira fica (ex.: "Carteira Digital"). Saldo em R$ dessa conta = saldo da carteira convertido. |
| Categorias | `carteira.categoria_consumo_id` = despesa do consumo. Receita usa a categoria padrão do negócio. |

## 3. Decisão de arquitetura (desvio consciente da especificação)
A especificação pedia despesa **na recarga** e despesa **no consumo**. Isso contaria o mesmo dinheiro duas vezes (R$ 100 de recarga + R$ 13 de consumo = R$ 113 de despesa para R$ 100 gastos). Implementado:
- **Recarga = transferência** para a conta da carteira (o dinheiro vira saldo pré-pago, um ativo; não é custo ainda).
- **Consumo = despesa** saindo da conta da carteira, ligada ao contrato/cliente (o custo aparece quando o app é ativado e entra na rentabilidade do contrato).
Resultado: DRE correta, saldo da conta "Carteira Digital" sempre igual ao saldo da carteira em R$, e custo por contrato mensurável. Se preferir reconhecer o custo na recarga, é uma troca de uma linha na RPC.

Outros ajustes menores: `taxa_conversao` é `numeric(10,4)` (0,1 crédito por R$ cabe; 2 casas não permitiriam 1 crédito = R$ 13). Colunas de data seguem a convenção do projeto (`criado_em`/`atualizado_em`). A carteira guarda `conta_id` e `categoria_consumo_id` (necessários para gerar os lançamentos). Transações têm `valor_reais` e `lancamento_id` (rastreabilidade financeira).

## 4. Regras
- Modo dinheiro **ou** créditos por negócio; crédito exige taxa (> 0). Exemplo: taxa 0,1 ⇒ R$ 50 = 5 créditos; app de 1,2 créditos ⇒ saldo 3,8 e despesa de R$ 12,00.
- Saldo nunca negativo (`check saldo >= 0` + verificação explícita com mensagem "Saldo insuficiente: disponível X, necessário Y").
- Transações da carteira: só o motor insere; **update/delete proibidos** (trigger), sem grants; auditoria em carteira, apps e transações.
- `carteira.saldo` é mantido por trigger a partir das transações (nunca gravado pelo cliente).
- A anuidade é registrada em `faturamentos`; o job diário não a duplica. Anos seguintes são faturados automaticamente pelo contrato.
- Ativação falha inteira (nada gravado) se o negócio não tiver conta/categoria de receita para faturar a anuidade.

## 5. Interface
- **Negócios → editar**: "Saldo para ativação de apps" (Não opera / Dinheiro / Créditos) e "Créditos por R$ 1,00" com prévia.
- **Apps** (novo item de menu): painel (saldo disponível, total recargas, total consumido, apps ativos, receita mensal = anuidades ativas ÷ 12, com o total anual), catálogo (criar/editar app: nome, custo, ativo; anuidade nasce no plano), carteira (histórico + **Recarregar**), **Ativar app** (cliente existente, app, data, anuidade opcional; prévia do saldo depois; bloqueado sem saldo), **Contratos de app** (cliente, app, anuidade, próximo vencimento, situação Ativo / Vencido / Cancelado).
- Vencido = anuidade prevista com vencimento no passado. Cancelado = contrato encerrado (no menu Contratos).

## 6. Banco (migration `20260902000013_apps_saldo.sql`)
Enums `tipo_saldo_app`, `tipo_transacao_carteira`; colunas em `negocios`; tabelas `carteira`, `apps_catalogo`, `transacoes_carteira`; RPCs `configurar_carteira`, `criar_app`, `recarregar_carteira`, `ativar_app`; views `vw_carteira_resumo`, `vw_contratos_app`; RLS por organização; grants: select (e update só em `apps_catalogo`) para `authenticated`, nada para `anon`.

## 7. Testes
- `supabase/tests/apps_saldo_test.sql`: configuração e regras, catálogo (plano anual, sincronização, duplicidade, insert direto bloqueado), fluxo dinheiro (recarga → transferência; ativação → saldo 85, contrato anual, receita prevista via faturamento sem duplicar, despesa vinculada, conta da carteira = saldo), fluxo créditos (50 → 5; 1,2 → 3,8; R$ 12), imutabilidade das transações e do saldo, situação vencido, `anon` negado.
- `supabase/tests/verificar_apps_saldo.sql`: 7 verificações somente leitura.
- e2e (Playwright + mock): configuração do negócio, carteira, catálogo, bloqueio sem saldo, recarga, ativação, painel, histórico e reflexos em Contas, Contratos e Lançamentos.

## 8. Como aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000013_apps_saldo.sql`.
2. `supabase/tests/verificar_apps_saldo.sql` → esperado **7 de 7**.
3. Deploy (push em `main`). Depois: Negócios → definir tipo de saldo; Apps → Configurar carteira → Novo app → Recarregar → Ativar app.
