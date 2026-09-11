# 36 · Monitoramento simples da OLT — Etapa 34 (migration `20260902000062_olt_monitoramento.sql`)

Primeiro componente fora do Supabase/Cloudflare: um **agente local** (mini-PC/Raspberry na central) pinga a OLT e reporta ao ERP. Sem NOC, sem tempo real.

- **Agente**: `supabase/scripts/olt-agente.sh` — bash + ping + curl, rodando por cron a cada 2 minutos. Configura código do POP, IP da OLT, URL da Edge e o segredo. O arquivo preenchido nunca vai ao GitHub.
- **Edge Function `olt-ping`** (Verify JWT desligado; segredo `OLT_PING_SECRET` no header): grava via `olt_registrar_ping` (service_role) e, quando o estado **muda** (caiu/voltou — nunca no primeiro ping), envia o aviso ao **WhatsApp do administrador** (numero_whatsapp da config de notificações do negócio) direto pela Evolution.
- **Banco**: `olt_status` (último estado por POP: online, latência, quando mudou) e `olt_eventos` (histórico só das mudanças). RLS por organização, escrita só service_role.
- **App**: alerta vermelho no topo da Rede FTTH quando algum POP está sem resposta (atualiza a cada 2 min).

### Para ativar (proprietário)
1. Deploy da Edge `olt-ping` (Verify JWT desligado) com secrets `OLT_PING_SECRET` (invente um valor longo), `EVOLUTION_API_URL` e `EVOLUTION_API_KEY` (os mesmos das notificações).
2. No mini-PC da central: copiar `olt-agente.sh`, preencher as 4 variáveis, `chmod +x` e agendar no cron (`*/2 * * * *`).
3. Testar: derrubar o ping (desconectar o cabo de teste) e conferir o aviso no WhatsApp.

## Testes

`supabase/tests/olt_test.sql`: primeiro ping registra sem avisar, repetição não gera evento, queda gera mudança, POP desconhecido tratado, histórico só de mudanças, estado atual correto. `verificar_tudo.sql`: **50 de 50**.
