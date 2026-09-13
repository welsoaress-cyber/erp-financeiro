// Edge Function: verificação ativa do Pix pelo PRÓPRIO cliente do portal (Verify JWT LIGADO).
// O portal chama esta função enquanto mostra o QR: ela reconsulta o pagamento na
// API do Mercado Pago (fonte da verdade) e, se aprovado, baixa a fatura na hora —
// sem depender do webhook do MP (cuja entrega é instável). Segura: só mexe na
// cobrança pendente do lançamento do cliente logado. Secrets: MP_ACCESS_TOKEN.
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

  const auth = req.headers.get('authorization') ?? ''
  const { lancamento_id } = await req.json().catch(() => ({}))
  if (!lancamento_id) return json({ ok: false, erro: 'lancamento_id obrigatório' }, 400)

  // cliente do portal logado
  const sbUser = createClient(SB_URL, SB_ANON, { global: { headers: { Authorization: auth } } })
  const { data: userData, error: eUser } = await sbUser.auth.getUser()
  if (eUser || !userData.user) return json({ ok: false, erro: 'não autenticado' }, 401)
  const { data: pessoaId, error: ePessoa } = await sbUser.rpc('portal_pessoa')
  if (ePessoa || !pessoaId) return json({ ok: false, erro: 'portal não vinculado' }, 403)

  // cobrança pendente do lançamento, do próprio cliente
  const sb = createClient(SB_URL, SB_SERVICE)
  const { data: cob } = await sb.from('pix_cobrancas')
    .select('txid, status')
    .eq('lancamento_id', lancamento_id)
    .eq('pessoa_id', pessoaId)
    .order('criado_em', { ascending: false })
    .limit(1).maybeSingle()
  if (!cob) return json({ ok: true, status: 'sem_cobranca', diag: 'sem cobrança pendente para este lançamento' })
  if (cob.status === 'pago') return json({ ok: true, status: 'pago' })
  if (cob.status !== 'pendente') return json({ ok: true, status: cob.status })

  // fonte da verdade: consulta o pagamento na API do MP
  const res = await fetch(`https://api.mercadopago.com/v1/payments/${cob.txid}`, { headers: { Authorization: `Bearer ${MP_TOKEN}` } })
  if (!res.ok) {
    const txt = await res.text().catch(() => '')
    console.log('pix-verificar consulta MP falhou', cob.txid, res.status, txt.slice(0, 200))
    return json({ ok: true, status: 'pendente', mp_status: `http_${res.status}`, diag: txt.slice(0, 160) })
  }
  const p = await res.json()
  console.log('pix-verificar', cob.txid, 'mp_status=', p.status)
  // grava o último status visto no MP no próprio registro (diagnóstico via SQL, sem cache)
  const diag = { ultimo_mp_status: p.status, checado_em: new Date().toISOString(), qr: (p.point_of_interaction?.transaction_data?.qr_code ?? '').slice(0, 60) }
  await sb.from('pix_cobrancas').update({ resposta: diag }).eq('txid', cob.txid).eq('status', 'pendente')
  if (p.status === 'approved') {
    const { error } = await sb.rpc('pix_confirmar', { p_txid: String(cob.txid), p_valor_pago: p.transaction_amount, p_resposta: { status: p.status, date_approved: p.date_approved, via: 'portal' } })
    if (error) return json({ ok: true, status: 'pendente', mp_status: 'approved', diag: `confirmar: ${error.message}` })
    return json({ ok: true, status: 'pago', mp_status: 'approved' })
  }
  if (p.status === 'cancelled' || p.status === 'expired' || p.status === 'rejected') {
    await sb.rpc('pix_marcar_erro', { p_txid: String(cob.txid), p_status: p.status === 'rejected' ? 'erro' : p.status === 'expired' ? 'expirado' : 'cancelado', p_resposta: { status: p.status } })
    return json({ ok: true, status: p.status, mp_status: p.status })
  }
  return json({ ok: true, status: 'pendente', mp_status: p.status })
})
