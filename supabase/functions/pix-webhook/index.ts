// Edge Function: webhook do Mercado Pago para pagamentos Pix.
// Deploy com "Verify JWT" DESLIGADO (o MP não manda JWT). Segurança: a função
// NUNCA confia no corpo do webhook — só pega o id e CONSULTA a API do MP com o
// token; a resposta da API é a fonte da verdade. Pagamento approved → baixa o
// lançamento (pix_confirmar, service_role).
// Configurar no painel do Mercado Pago: Webhooks → URL desta função, evento "Pagamentos".
// Secrets: MP_ACCESS_TOKEN.
import { createClient } from 'npm:@supabase/supabase-js@2'

const SB_URL = Deno.env.get('SUPABASE_URL')!
const SB_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const MP_TOKEN = (Deno.env.get('MP_ACCESS_TOKEN') ?? '').trim()

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ ok: true }) // MP testa com GET às vezes
  if (!MP_TOKEN) return json({ ok: false, erro: 'MP_ACCESS_TOKEN não configurado' }, 500)

  const url = new URL(req.url)
  const corpo = await req.json().catch(() => ({}))
  const tipo = corpo?.type ?? corpo?.topic ?? url.searchParams.get('topic') ?? url.searchParams.get('type')
  const id = corpo?.data?.id ?? url.searchParams.get('data.id') ?? url.searchParams.get('id')
  if (!id || (tipo && !String(tipo).includes('payment'))) return json({ ok: true, ignorado: true })

  // fonte da verdade: consulta o pagamento na API do MP
  const res = await fetch(`https://api.mercadopago.com/v1/payments/${id}`, { headers: { Authorization: `Bearer ${MP_TOKEN}` } })
  if (!res.ok) return json({ ok: false, erro: `consulta MP: ${res.status}` }, 200) // 200 para o MP não repetir eternamente
  const p = await res.json()

  const sb = createClient(SB_URL, SB_SERVICE)
  if (p.status === 'approved') {
    const { data, error } = await sb.rpc('pix_confirmar', { p_txid: String(p.id), p_valor_pago: p.transaction_amount, p_resposta: { status: p.status, date_approved: p.date_approved } })
    if (error) return json({ ok: false, erro: error.message }, 200)
    return json({ ok: true, resultado: data })
  }
  if (p.status === 'cancelled' || p.status === 'expired' || p.status === 'rejected') {
    await sb.rpc('pix_marcar_erro', { p_txid: String(p.id), p_status: p.status === 'rejected' ? 'erro' : p.status === 'expired' ? 'expirado' : 'cancelado', p_resposta: { status: p.status } })
  }
  return json({ ok: true, status: p.status })
})
