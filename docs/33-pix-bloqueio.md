# 33 · Pix automático + Bloqueio assistido — Etapa 31 (migration `20260902000059_pix_bloqueio.sql`)

## Pix (Mercado Pago — custo autorizado: taxa por transação, ~0,99% no Pix)

- **Portal**: nas faturas em aberto aparece "Pagar com Pix" → Edge Function `pix-gerar` cria o pagamento no MP e devolve o **copia-e-cola** (+ link do QR). Cobrança pendente é reaproveitada (não gera duplicada). O cliente só vê as próprias faturas (validação dupla: JWT + vínculo do portal).
- **Baixa automática**: o MP chama a Edge `pix-webhook` (Verify JWT desligado); a função **consulta a API do MP** com o token (nunca confia no corpo do webhook) e, aprovado, `pix_confirmar` baixa o lançamento na **conta Pix** configurada do negócio. Idempotente. A baixa usa `pix_efetivar_interno`, espelho privado de `efetivar_lancamento` (0041) sem checagem de membro — revogado de todos, chamável só pelo motor service_role (se `efetivar_lancamento` mudar no futuro, atualizar o espelho).
- **Aviso de cobrança**: `notificacoes-enviar` (Evolution) passa a anexar o copia-e-cola nas mensagens de vencimento/bloqueio quando o Pix está ativo no negócio.
- **Config**: Portal → Configurar → "Pix automático" + conta que recebe. Token **só** nos secrets das Edge Functions (`MP_ACCESS_TOKEN` em `pix-gerar`, `pix-webhook` e `notificacoes-enviar`). Nada no banco/repositório.
- `pix_cobrancas`: txid, valor, copia-e-cola, status (pendente/pago/expirado/cancelado/erro), auditada, RLS org (admin lê; portal só via `portal_pix_cobranca`). Funções de escrita: `service_role`.

### Para ativar (proprietário)
1. Conta Mercado Pago da Servnet → Suas integrações → criar aplicação → **Access Token de produção**.
2. Painel Supabase → Edge Functions → Deploy `pix-gerar` (Verify JWT **ligado**) e `pix-webhook` (Verify JWT **desligado**); re-deploy `notificacoes-enviar`. Secret `MP_ACCESS_TOKEN` nas três.
3. No painel do MP → Webhooks → URL da `pix-webhook` → evento **Pagamentos**.
4. No ERP: Portal → Configurar → ligar "Pix automático" e escolher a conta.
5. Testar com uma fatura pequena real (o MP não tem sandbox de Pix no fluxo simples).

## Bloqueio assistido (sem corte automático)

- **Financeiro → Cobrança**: a tela monta a lista ao abrir (`gerar_bloqueios`): **Bloquear** = contrato ativo com cobrança vencida além do prazo da régua (`dias_apos` da config de notificações; padrão 3); **Desbloquear** = contrato suspenso sem vencidas. Sem duplicar pendências; as que deixam de valer são descartadas sozinhas.
- Admin executa no sistema de rede e clica "Bloqueei/Desbloqueei na rede" → o contrato muda de status (ativo ↔ suspenso) e fica auditado. "Ignorar" descarta.
- Pix recentes na mesma tela (quem pagou, quem está aguardando).

## Testes

`supabase/tests/pix_bloqueio_test.sql`: fila de dados do Pix, registro com reaproveitamento/cancelamento de pendente, webhook confirma e baixa na conta Pix (idempotente, txid desconhecido tratado), usuário comum não chama funções de service, admin vê cobranças; bloqueio sugerido sem duplicar, executar suspende, pagamento sugere desbloqueio, executar reativa, repetição bloqueada. `verificar_tudo.sql`: **47 de 47**.
