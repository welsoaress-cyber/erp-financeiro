// Edge Function: consulta de cliente por CPF/CNPJ para integrações externas
// (hoje: Leveduca). Deploy com "Verify JWT" DESLIGADO — quem chama é o sistema
// da Leveduca, não um usuário logado no ERP; a autenticação é o header Token,
// validado contra o hash gravado em api_tokens. A consulta inteira roda na
// função definer api_consultar_cliente (0096): a Edge Function não lê tabela
// nenhuma diretamente — só chama o RPC com a service role, que só precisa de
// EXECUTE na função (evita depender de grant tabela por tabela pro service_role,
// que no Supabase hospedado não é automático pra tabela criada pela SQL Editor).
// Nenhum secret novo: usa só SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.
import { createClient } from 'npm:@supabase/supabase-js@2'

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } })
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, token', 'Access-Control-Allow-Methods': 'POST, OPTIONS' }
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

async function sha256Hex(texto: string): Promise<string> {
  const dados = new TextEncoder().encode(texto)
  const hash = await crypto.subtle.digest('SHA-256', dados)
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ erro: 'Método não permitido.' }, 405)

  // aceita "Token: <valor>" (como no exemplo da Leveduca) ou "Authorization: Bearer <valor>"
  const tokenBruto = req.headers.get('token') ?? (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
  const token = tokenBruto.trim()
  if (!token) return json({ erro: 'Token não informado.' }, 401)

  let corpo: { cpf_cnpj?: string } = {}
  try { corpo = await req.json() } catch { return json({ erro: 'Corpo inválido — envie {"cpf_cnpj": "..."}.' }, 400) }
  const documento = String(corpo.cpf_cnpj ?? '').replace(/\D/g, '')
  if (documento.length !== 11 && documento.length !== 14) return json({ erro: 'Informe um CPF ou CNPJ válido em cpf_cnpj.' }, 400)

  const hash = await sha256Hex(token)
  const { data, error } = await sb.rpc('api_consultar_cliente', { p_token_hash: hash, p_documento: documento })
  if (error) { console.error('api_consultar_cliente', error.message); return json({ erro: 'Falha na consulta.' }, 500) }

  const linha = (data as { situacao: string; cliente: Record<string, unknown> | null }[])[0]
  if (!linha || linha.situacao === 'token_invalido') return json({ erro: 'Token inválido ou revogado.' }, 401)
  if (linha.situacao === 'nao_encontrado') return json({ erro: 'Cliente não encontrado.' }, 404)

  return json({ cliente: linha.cliente })
})
