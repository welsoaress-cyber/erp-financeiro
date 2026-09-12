// Edge Function: reconciliação ativa do Pix (Verify JWT LIGADO — admin logado).
// Segurança do fluxo: cobranças "pendente" com mais de 1 hora são re-consultadas
// direto na API do Mercado Pago (a mesma fonte da verdade do webhook). Pagou e o
// webhook se perdeu → pix_confirmar dá a baixa agora; cancelado/expirado/rejeitado
// → pix_marcar_erro. Assim nunca se bloqueia cliente que pagou.
// Chamada pela tela Financeiro → Cobrança ao abrir. Secrets: MP_ACCESS_TOKEN.
import { createClient } from 'npm:@supabase/supabase-js@2'

const SB_URL = Deno.env.get('SUPABASE_URL')!
const SB_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const SB_ANON = Deno.env.get('SUPABASE_ANON_KEY')!
const MP_TOKEN = (Deno.env.get('MP_ACCESS_TOKEN') ?? '').trim()

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' },
})

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return json({ ok: true })
  if (req.method !== 'POST') return json({ ok: false, erro: 'método' }, 405)
  if (!MP_TOKEN) return json({ ok: false, erro: 'MP_ACCESS_TOKEN não configurado' }, 500)

  // quem chama precisa ser membro da organização (admin) — cliente do portal não passa
  const auth = req.headers.get('authorization') ?? ''
  const sbUser = createClient(SB_URL, SB_ANON, { global: { headers: { Authorization: auth } } })
  const { data: userData, error: eUser } = await sbUser.auth.getUser()
  if (eUser || !userData.user) return json({ ok: false, erro: 'não autenticado' }, 401)

  const sb = createClient(SB_URL, SB_SERVICE)
  const { data: membro } = await sb.from('organizacao_membros').select('organizacao_id').eq('usuario_id', userData.user.id).maybeSingle()
  if (!membro?.organizacao_id) return json({ ok: false, erro: 'apenas administradores' }, 403)

  // cobranças aguardando há mais de 1h (webhook pode ter se perdido)
  const corte = new Date(Date.now() - 60 * 60 * 1000).toISOString()
  const { data: pendentes, error: ePend } = await sb
    .from('pix_cobrancas')
    .select('txid')
    .eq('organizacao_id', membro.organizacao_id)
    .eq('status', 'pendente')
    .lt('criado_em', corte)
    .order('criado_em')
    .limit(25)
  if (ePend) return json({ ok: false, erro: ePend.message }, 500)

  let confirmados = 0
  let encerrados = 0
  for (const c of pendentes ?? []) {
    const res = await fetch(`https://api.mercadopago.com/v1/payments/${c.txid}`, { headers: { Authorization: `Bearer ${MP_TOKEN}` } })
    if (!res.ok) continue
    const p = await res.json()
    if (p.status === 'approved') {
      const { error } = await sb.rpc('pix_confirmar', { p_txid: String(p.id), p_valor_pago: p.transaction_amount, p_resposta: { status: p.status, date_approved: p.date_approved, reconciliado: true } })
      if (!error) confirmados++
    } else if (p.status === 'cancelled' || p.status === 'expired' || p.status === 'rejected') {
      const { error } = await sb.rpc('pix_marcar_erro', { p_txid: String(p.id), p_status: p.status === 'rejected' ? 'erro' : p.status === 'expired' ? 'expirado' : 'cancelado', p_resposta: { status: p.status, reconciliado: true } })
      if (!error) encerrados++
    }
  }
  return json({ ok: true, verificados: (pendentes ?? []).length, confirmados, encerrados })
})
