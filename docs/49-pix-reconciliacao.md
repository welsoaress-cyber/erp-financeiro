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
