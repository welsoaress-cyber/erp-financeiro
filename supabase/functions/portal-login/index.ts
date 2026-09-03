// Edge Function: login do portal sem senha (CPF/CNPJ + data de nascimento), como no portal antigo da SERVNET.
// Fluxo: portal_login_verificar (freio de 5 tentativas/15 min no banco) → usuário técnico do Auth (criado na
// primeira vez, e-mail sintético <pessoa_id>@portal.erp.local, metadata portal=true) → portal_vincular_servico →
// link mágico (token_hash) que o navegador troca por sessão com supabase.auth.verifyOtp.
// Deploy com "Verify JWT" desligado (é chamada por quem ainda não tem sessão). Só usa SUPABASE_URL e
// SUPABASE_SERVICE_ROLE_KEY, injetados pela plataforma — nenhum secret novo.
import { createClient } from 'npm:@supabase/supabase-js@2'

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } })
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' }
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
const emailSintetico = (pessoaId: string) => `${pessoaId}@portal.erp.local`

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ ok: false, msg: 'método' }, 405)
  let corpo: { documento?: string; nascimento?: string } = {}
  try { corpo = await req.json() } catch { return json({ ok: false, msg: 'Corpo inválido.' }, 400) }
  const documento = String(corpo.documento ?? '').replace(/\D/g, '')
  const nascimento = String(corpo.nascimento ?? '')
  if (!documento || !/^\d{4}-\d{2}-\d{2}$/.test(nascimento)) return json({ ok: false, msg: 'Informe o CPF/CNPJ e a data de nascimento.' }, 400)

  const { data: v, error: e1 } = await sb.rpc('portal_login_verificar', { p_documento: documento, p_nascimento: nascimento })
  if (e1) { console.error('portal_login_verificar', e1.message); return json({ ok: false, msg: 'Falha ao verificar os dados. Tente novamente.' }, 500) }
  const ver = v as { ok: boolean; msg?: string; pessoa_id?: string; nome?: string; email?: string | null }
  if (!ver.ok) return json({ ok: false, msg: ver.msg ?? 'Dados não conferem.' }, 401)
  const pessoaId = ver.pessoa_id!

  // usuário técnico: reaproveita o acesso existente (inclusive o criado por e-mail/senha) ou cria um novo
  let email: string | null = null
  const { data: acesso } = await sb.from('portal_acessos').select('usuario_id').eq('pessoa_id', pessoaId).maybeSingle()
  if (acesso?.usuario_id) {
    const { data: u } = await sb.auth.admin.getUserById(acesso.usuario_id)
    email = u?.user?.email ?? null
  }
  if (!email) {
    email = emailSintetico(pessoaId)
    const { data: criado, error: e2 } = await sb.auth.admin.createUser({ email, email_confirm: true, user_metadata: { portal: 'true', nome: ver.nome, login: 'documento' } })
    if (e2 && !/already|exists|registered/i.test(e2.message)) { console.error('createUser', e2.message); return json({ ok: false, msg: 'Não foi possível preparar seu acesso.' }, 500) }
    if (criado?.user) {
      const { error: e3 } = await sb.rpc('portal_vincular_servico', { p_pessoa_id: pessoaId, p_usuario_id: criado.user.id })
      if (e3) { console.error('portal_vincular_servico', e3.message); return json({ ok: false, msg: e3.message }, 409) }
    }
  }
  const { data: link, error: e4 } = await sb.auth.admin.generateLink({ type: 'magiclink', email })
  if (e4 || !link?.properties?.hashed_token) { console.error('generateLink', e4?.message); return json({ ok: false, msg: 'Não foi possível gerar seu acesso.' }, 500) }
  if (!acesso?.usuario_id && link.user?.id) await sb.rpc('portal_vincular_servico', { p_pessoa_id: pessoaId, p_usuario_id: link.user.id })
  return json({ ok: true, token_hash: link.properties.hashed_token, nome: ver.nome })
})
