// Edge Function: aceite digital do contrato pelo portal (Verify JWT LIGADO).
// O cliente logado aceita o termo; a função resolve a pessoa pelo vínculo do
// portal (portal_acessos), captura IP e user-agent da requisição e grava via
// registrar_aceite_contrato (service_role) — snapshot do texto + hash.
// Nenhum secret além dos injetados pela plataforma.
import { createClient } from 'npm:@supabase/supabase-js@2'

const SB_URL = Deno.env.get('SUPABASE_URL')!
const SB_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const SB_ANON = Deno.env.get('SUPABASE_ANON_KEY')!

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' },
})

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return json({ ok: true })
  if (req.method !== 'POST') return json({ ok: false, erro: 'método' }, 405)

  const auth = req.headers.get('authorization') ?? ''
  const sbUser = createClient(SB_URL, SB_ANON, { global: { headers: { Authorization: auth } } })
  const { data: userData, error: eUser } = await sbUser.auth.getUser()
  if (eUser || !userData.user) return json({ ok: false, erro: 'não autenticado' }, 401)

  const sb = createClient(SB_URL, SB_SERVICE)
  const { data: acesso } = await sb.from('portal_acessos').select('pessoa_id').eq('usuario_id', userData.user.id).maybeSingle()
  if (!acesso?.pessoa_id) return json({ ok: false, erro: 'portal não vinculado' }, 403)

  const corpo = await req.json().catch(() => ({}))
  const contratoId = String(corpo?.contrato_id ?? '')
  if (!contratoId) return json({ ok: false, erro: 'contrato não informado' }, 400)

  const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() || null
  const userAgent = req.headers.get('user-agent') ?? ''

  const { data, error } = await sb.rpc('registrar_aceite_contrato', {
    p_contrato_id: contratoId,
    p_pessoa_id: acesso.pessoa_id,
    p_ip: ip,
    p_user_agent: userAgent,
  })
  if (error) return json({ ok: false, erro: error.message }, 400)
  return json({ ok: true, data_aceite: data?.data_aceite ?? null })
})
