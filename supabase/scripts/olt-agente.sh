#!/usr/bin/env bash
# Agente de monitoramento da OLT — roda num mini-PC/Raspberry NA REDE da central.
# Pinga o IP da OLT e reporta ao ERP (Edge Function olt-ping). Sem NOC: o ERP
# avisa no WhatsApp do administrador só quando o estado MUDA (caiu/voltou).
#
# Instalação (uma vez):
#   1. Edite as 4 variáveis abaixo.
#   2. chmod +x olt-agente.sh
#   3. crontab -e  →  */2 * * * * /caminho/olt-agente.sh >/dev/null 2>&1
#
# NUNCA suba este arquivo preenchido para o GitHub (o segredo fica só no mini-PC).
POP_CODIGO="POP-01"                                   # código do POP no ERP
OLT_IP="10.0.0.2"                                     # IP da OLT na rede local
ERP_URL="https://SEU-REF.supabase.co/functions/v1/olt-ping"
SEGREDO="COLOQUE-O-MESMO-OLT_PING_SECRET-DA-EDGE"

if ping -c 2 -W 2 "$OLT_IP" >/dev/null 2>&1; then
  LAT=$(ping -c 3 -W 2 "$OLT_IP" | tail -1 | awk -F'/' '{printf "%d", $5}')
  BODY="{\"pop\":\"$POP_CODIGO\",\"online\":true,\"latencia_ms\":${LAT:-0}}"
else
  BODY="{\"pop\":\"$POP_CODIGO\",\"online\":false}"
fi
curl -sS -m 15 -X POST "$ERP_URL" -H "Content-Type: application/json" -H "x-olt-secret: $SEGREDO" -d "$BODY" >/dev/null
