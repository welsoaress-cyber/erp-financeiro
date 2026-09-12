// Edge Function: gera cobrança Pix no Mercado Pago para uma fatura do portal.
// Chamada pelo app do PORTAL com o JWT do cliente logado (Verify JWT LIGADO).
// A função valida com o service_role que a fatura pertence ao cliente logado
// (portal_pessoa) e que o Pix está ativo no negócio; reaproveita cobrança
// pendente. Secrets necessários:
//   MP_ACCESS_TOKEN        access token de produção do Mercado Pago
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são injetados pela plataforma.
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

  // 1) quem chama é um cliente do portal? (JWT do usuário)
  const sbUser = createClient(SB_URL, SB_ANON, { global: { headers: { Authorization: auth } } })
  const { data: userData, error: eUser } = await sbUser.auth.getUser()
  if (eUser || !userData.user) return json({ ok: false, erro: 'não autenticado' }, 401)

  // resolve a pessoa como o resto do portal: portal_pessoa() com o JWT do cliente
  const { data: pessoaId, error: ePessoa } = await sbUser.rpc('portal_pessoa')
  if (ePessoa || !pessoaId) return json({ ok: false, erro: 'portal não vinculado' }, 403)

  const sb = createClient(SB_URL, SB_SERVICE)

  // 2) fatura válida, do cliente, com Pix ativo no negócio
  const { data: dados, error: eDados } = await sb.rpc('pix_dados_lancamento', { p_lancamento_id: lancamento_id })
  const d = Array.isArray(dados) ? dados[0] : dados
  if (eDados || !d) return json({ ok: false, erro: 'fatura não encontrada ou já paga' }, 404)
  if (d.pessoa_id !== pessoaId) return json({ ok: false, erro: 'fatura de outro cliente' }, 403)
  if (!d.pix_automatico) return json({ ok: false, erro: 'Pix automático não está ativo para este serviço' }, 400)
  if (d.cobranca_pendente) return json({ ok: true, copia_cola: d.cobranca_pendente, reaproveitada: true })

  // 3) cria o pagamento Pix no Mercado Pago
  const documento = String(d.documento ?? '').replace(/\D/g, '')
  const corpo = {
    transaction_amount: Number(d.valor),
    description: `${d.descricao} (venc. ${d.vencimento})`,
    payment_method_id: 'pix',
    date_of_expiration: new Date(Date.now() + 24 * 3600 * 1000).toISOString().replace('Z', '-00:00'),
    external_reference: String(lancamento_id),
    payer: {
      email: d.email || 'cliente@sememail.com.br',
      first_name: String(d.cliente ?? 'Cliente').split(' ')[0],
      identification: documento.length === 11 ? { type: 'CPF', number: documento } : documento.length === 14 ? { type: 'CNPJ', number: documento } : undefined,
    },
  }
  const res = await fetch('https://api.mercadopago.com/v1/payments', {
    method: 'POST',
    headers: { Authorization: `Bearer ${MP_TOKEN}`, 'Content-Type': 'application/json', 'X-Idempotency-Key': `pix-${lancamento_id}-${Date.now()}` },
    body: JSON.stringify(corpo),
  })
  const mp = await res.json().catch(() => ({}))
  if (!res.ok) return json({ ok: false, erro: `Mercado Pago: ${mp?.message ?? res.status}` }, 502)

  const copiaCola = mp?.point_of_interaction?.transaction_data?.qr_code
  const ticket = mp?.point_of_interaction?.transaction_data?.ticket_url
  const qrBase64 = mp?.point_of_interaction?.transaction_data?.qr_code_base64 ?? null
  if (!copiaCola) return json({ ok: false, erro: 'Mercado Pago não devolveu o código Pix' }, 502)

  // 4) registra no banco (motor service_role)
  const { error: eReg } = await sb.rpc('pix_registrar', {
    p_lancamento_id: lancamento_id, p_txid: String(mp.id), p_copia_cola: copiaCola,
    p_ticket_url: ticket ?? null, p_expira_em: corpo.date_of_expiration, p_resposta: { status: mp.status },
  })
  if (eReg) return json({ ok: false, erro: `registro: ${eReg.message}` }, 500)
  return json({ ok: true, copia_cola: copiaCola, ticket_url: ticket ?? null, qr_base64: qrBase64, expira_em: corpo.date_of_expiration })
})
