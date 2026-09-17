// Edge Function: consulta de cliente por CPF/CNPJ para integrações externas
// (hoje: Leveduca). Deploy com "Verify JWT" DESLIGADO — quem chama é o sistema
// da Leveduca, não um usuário logado no ERP; a autenticação é o header Token,
// validado contra o hash gravado em api_tokens. Roda com a service role porque
// não existe sessão nossa aqui (bypassa RLS de propósito, igual ao portal-login).
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

const ROTULO_STATUS_CONTRATO: Record<string, string> = { ativo: 'Ativo', suspenso: 'Suspenso', encerrado: 'Encerrado' }

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
  const { data: tk, error: eTk } = await sb.from('api_tokens').select('id, organizacao_id, negocio_id, ativo').eq('token_hash', hash).maybeSingle()
  if (eTk) { console.error('api_tokens', eTk.message); return json({ erro: 'Falha ao validar o token.' }, 500) }
  if (!tk || !tk.ativo) return json({ erro: 'Token inválido ou revogado.' }, 401)

  void sb.from('api_tokens').update({ ultimo_uso_em: new Date().toISOString() }).eq('id', tk.id).then(() => undefined)

  const { data: pessoa, error: eP } = await sb.from('pessoas')
    .select('id, nome, documento, email, endereco, ativo')
    .eq('organizacao_id', tk.organizacao_id).eq('documento', documento).maybeSingle()
  if (eP) { console.error('pessoas', eP.message); return json({ erro: 'Falha na consulta.' }, 500) }

  async function registrarLog(encontrado: boolean) {
    await sb.from('api_consultas').insert({ organizacao_id: tk!.organizacao_id, token_id: tk!.id, documento_consultado: documento, encontrado })
  }

  if (!pessoa) { await registrarLog(false); return json({ erro: 'Cliente não encontrado.' }, 404) }

  // contrato de receita mais relevante desse negócio: ativo primeiro, depois suspenso, senão o mais recente
  const { data: contratos, error: eC } = await sb.from('contratos')
    .select('id, status, criado_em, plano_id, planos ( nome )')
    .eq('negocio_id', tk.negocio_id).eq('pessoa_id', pessoa.id).eq('tipo_financeiro', 'receita')
    .order('criado_em', { ascending: false }).limit(20)
  if (eC) { console.error('contratos', eC.message); return json({ erro: 'Falha na consulta.' }, 500) }
  type Contrato = { id: string; status: string; plano_id: string; planos: { nome: string } | null }
  const prioridade: Record<string, number> = { ativo: 0, suspenso: 1, encerrado: 2 }
  const contrato = ((contratos ?? []) as Contrato[]).sort((a, b) => (prioridade[a.status] ?? 9) - (prioridade[b.status] ?? 9))[0]

  await registrarLog(true)

  const statusCliente = !pessoa.ativo ? 'Inativo' : contrato?.status === 'ativo' ? 'Ativo' : contrato?.status === 'suspenso' ? 'Suspenso' : 'Inativo'

  return json({
    cliente: {
      cpf_cnpj: pessoa.documento,
      nome_completo: pessoa.nome,
      status_cliente: statusCliente,
      email: pessoa.email ?? null,
      endereco: pessoa.endereco ?? null, // sem accent no JSON de propósito (evita encoding zoado do lado deles)
      numero: null, // não temos número separado do endereço — vem tudo junto no campo acima
      cep: null,    // idem
      plano: contrato?.planos?.nome ?? null,
      plano_id: contrato?.plano_id ?? null,
      status_plano: contrato ? (ROTULO_STATUS_CONTRATO[contrato.status] ?? contrato.status) : null,
    },
  })
})
