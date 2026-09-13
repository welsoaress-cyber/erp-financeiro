# Etapa 46 — Reconciliação ativa do Pix

## Problema
O webhook do Mercado Pago é ponto único de falha silencioso: se a entrega
falhar, o pagamento não dá baixa e o admin pode bloquear cliente que pagou.

## Solução (sem migration)
Edge Function **`pix-reconciliar`** (Verify JWT LIGADO, só membro da
organização): busca as cobranças `pendente` com **mais de 1 hora** (até 25
por chamada) e re-consulta cada uma na API do Mercado Pago — a mesma fonte
da verdade do webhook. `approved` → `pix_confirmar` (baixa + desbloqueio
sugerido); `cancelled/expired/rejected` → `pix_marcar_erro`.

A tela **Financeiro → Cobrança** chama a função ao abrir e mostra o
resultado no cabeçalho de "Pix recentes" ("N verificados · N baixados
agora"). Se a Edge estiver indisponível, a tela segue normalmente.

## Ativação (proprietário)
Deploy da função `pix-reconciliar` no painel do Supabase (Edge Functions →
Deploy, Verify JWT LIGADO). Usa o mesmo secret `MP_ACCESS_TOKEN` já
configurado para o Pix — nada novo.


## Verificação ativa no portal (pix-verificar)
O portal, enquanto mostra o QR, chama a Edge `pix-verificar` a cada 4s: ela reconsulta o pagamento na API do Mercado Pago e baixa a fatura na hora se aprovado — o cliente vê "Pago" em segundos sem depender da entrega do webhook do MP (instável). Verify JWT ligado; só age na cobrança pendente do próprio cliente.

## Reconciliação dentro do banco, a cada minuto (0077 — definitiva)
A baixa automática deixou de depender de webhook do MP, de Edge chamada pelo
navegador ou do pagamento criado virar "approved". `pix_reconciliar_agendado()`
(pg_cron a cada 1 min, pg_net, token no Vault `mp_access_token`) consulta o
Mercado Pago para cada cobrança pendente dos últimos 3 dias de duas formas —
`GET /v1/payments/{txid}` e `GET /v1/payments/search?external_reference={fatura}`
(o dinheiro pode entrar num pagamento separado) — grava o status real em
`pix_cobrancas.resposta` (`ultimo_mp_status`, `busca_ref`; diagnóstico sem
cache) e chama `pix_confirmar` no primeiro `approved`. pg_net é assíncrono:
dispara num minuto e processa a resposta no seguinte (`pix_verificacoes` guarda
as requisições em voo; sem resposta em 5 min, tenta de novo). Validada
localmente com stubs de net/vault/cron (cenário GET pending + busca approved).
Webhook, `pix-verificar` (portal) e `pix-reconciliar` (Cobrança) continuam
como caminhos rápidos; o cron é a garantia.
