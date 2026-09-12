// Edge Function: envia as notificações pendentes (provedor "evolution") pela Evolution API.
// Chamada pelo pg_cron (migration 0019) com o cabeçalho x-cron-secret, ou manualmente com o mesmo segredo.
// Secrets necessários (painel Supabase → Edge Functions → Secrets):
//   EVOLUTION_API_URL   ex.: http://IP-DA-VM:8080   (sem barra no fim)
//   EVOLUTION_API_KEY   apikey da Evolution
//   NOTIFICACOES_CRON_SECRET  mesmo valor guardado no Vault
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são injetados automaticamente pela plataforma.
// Deploy com "Verify JWT" desligado (a autenticação é o segredo do cron).
import { createClient } from 'npm:@supabase/supabase-js@2'

const SB_URL = Deno.env.get('SUPABASE_URL')!
const SB_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const EVO_URL = (Deno.env.get('EVOLUTION_API_URL') ?? '').replace(/\/$/, '')
const EVO_KEY = Deno.env.get('EVOLUTION_API_KEY') ?? ''
const CRON_SECRET = Deno.env.get('NOTIFICACOES_CRON_SECRET') ?? ''
// Pix no aviso de cobrança (etapa 31): com MP_ACCESS_TOKEN configurado e Pix
// ativo no negócio, o aviso ganha o copia-e-cola no fim da mensagem.
const MP_TOKEN = (Deno.env.get('MP_ACCESS_TOKEN') ?? '').trim()

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

// Gera (ou reaproveita) a cobrança Pix da fatura; devolve o copia-e-cola ou null.
// deno-lint-ignore no-explicit-any
async function pixDaFatura(sb: any, lancamentoId: string): Promise<string | null> {
  if (!MP_TOKEN || !lancamentoId) return null
  try {
    const { data } = await sb.rpc('pix_dados_lancamento', { p_lancamento_id: lancamentoId })
    const d = Array.isArray(data) ? data[0] : data
    if (!d || !d.pix_automatico) return null
    if (d.cobranca_pendente) return d.cobranca_pendente as string
    const documento = String(d.documento ?? '').replace(/\D/g, '')
    const res = await fetch('https://api.mercadopago.com/v1/payments', {
      method: 'POST',
      headers: { Authorization: `Bearer ${MP_TOKEN}`, 'Content-Type': 'application/json', 'X-Idempotency-Key': `aviso-${lancamentoId}-${Date.now()}` },
      body: JSON.stringify({
        transaction_amount: Number(d.valor),
        description: `${d.descricao} (venc. ${d.vencimento})`,
        payment_method_id: 'pix',
        date_of_expiration: new Date(Date.now() + 48 * 3600 * 1000).toISOString().replace('Z', '-00:00'),
        external_reference: String(lancamentoId),
        payer: {
          email: d.email || 'cliente@sememail.com.br',
          first_name: String(d.cliente ?? 'Cliente').split(' ')[0],
          identification: documento.length === 11 ? { type: 'CPF', number: documento } : documento.length === 14 ? { type: 'CNPJ', number: documento } : undefined,
        },
      }),
    })
    const mp = await res.json().catch(() => ({}))
    const codigo = mp?.point_of_interaction?.transaction_data?.qr_code
    if (!res.ok || !codigo) return null
    await sb.rpc('pix_registrar', {
      p_lancamento_id: lancamentoId, p_txid: String(mp.id), p_copia_cola: codigo,
      p_ticket_url: mp?.point_of_interaction?.transaction_data?.ticket_url ?? null,
      p_expira_em: new Date(Date.now() + 48 * 3600 * 1000).toISOString(), p_resposta: { status: mp.status, origem: 'aviso' },
    })
    return codigo as string
  } catch { return null }
}
const mascarar = (n: string | null) => (n ?? '').replace(/\d(?=\d{4})/g, '*')
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

async function estadoInstancia(instancia: string): Promise<{ ok: boolean; estado: string }> {
  try {
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 8000)
    const res = await fetch(`${EVO_URL}/instance/connectionState/${instancia}`, { headers: { apikey: EVO_KEY }, signal: ctl.signal })
    clearTimeout(t)
    if (!res.ok) return { ok: false, estado: `HTTP ${res.status}` }
    const j = await res.json()
    const estado: string = j?.instance?.state ?? j?.state ?? 'desconhecido'
    return { ok: estado === 'open', estado }
  } catch (e) { return { ok: false, estado: `rede: ${String(e)}` } }
}

async function enviarTexto(instancia: string, numero: string, texto: string): Promise<{ ok: boolean; erro?: string; resposta?: unknown }> {
  let ultimoErro = ''
  for (let tentativa = 1; tentativa <= 3; tentativa++) {
    try {
      const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 15000)
      const res = await fetch(`${EVO_URL}/message/sendText/${instancia}`, {
        method: 'POST', headers: { apikey: EVO_KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify({ number: numero.replace(/\D/g, ''), text: texto }), signal: ctl.signal,
      })
      clearTimeout(t)
      const corpo = await res.text()
      let resposta: unknown = corpo; try { resposta = JSON.parse(corpo) } catch { /* texto puro */ }
      if (res.ok) return { ok: true, resposta }
      ultimoErro = `HTTP ${res.status}: ${corpo.slice(0, 300)}`
    } catch (e) { ultimoErro = String(e) }
    if (tentativa < 3) await sleep(1000 * tentativa)
  }
  return { ok: false, erro: ultimoErro }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST' && req.method !== 'GET') return json({ ok: false, erro: 'método' }, 405)
  const auth = req.headers.get('authorization') ?? ''
  const fornecido = req.headers.get('x-cron-secret') ?? (auth.startsWith('Bearer ') ? auth.slice(7) : '')
  if (!CRON_SECRET || fornecido !== CRON_SECRET) return json({ ok: false, erro: 'não autorizado' }, 401)
  if (!EVO_URL || !EVO_KEY) return json({ ok: false, erro: 'EVOLUTION_API_URL/EVOLUTION_API_KEY não configurados' }, 500)

  const sb = createClient(SB_URL, SB_SERVICE)
  // lote pequeno + pausa longa entre mensagens: proteção do número contra bloqueio do WhatsApp
  const { data: fila, error } = await sb.rpc('notificacoes_para_envio', { p_limite: 8 })
  if (error) return json({ ok: false, erro: error.message }, 500)
  const itens = (fila ?? []) as Array<{ id: string; instancia: string; numero_destino: string; mensagem: string; tipo: string }>
  if (itens.length === 0) return json({ ok: true, enviados: 0, erros: 0, pulados: 0, msg: 'Nada pendente.' })

  const estados = new Map<string, { ok: boolean; estado: string }>()
  let enviados = 0, erros = 0, pulados = 0
  const resultados: Array<{ id: string; destino: string; status: string; motivo?: string }> = []
  for (const it of itens) {
    if (!estados.has(it.instancia)) estados.set(it.instancia, await estadoInstancia(it.instancia))
    const st = estados.get(it.instancia)!
    if (!st.ok) {
      pulados++
      const motivo = `Instância '${it.instancia}' desconectada do WhatsApp (${st.estado}). Reconecte na Evolution; o aviso continua pendente.`
      await sb.rpc('registrar_resultado_notificacao', { p_id: it.id, p_ok: false, p_erro: motivo, p_resposta: null, p_contar: false })
      resultados.push({ id: it.id, destino: mascarar(it.numero_destino), status: 'pulado', motivo })
      continue
    }
    let mensagem = it.mensagem
    if (['proximo_vencimento', 'vencimento', 'bloqueio'].includes(it.tipo)) {
      const { data: log } = await sb.from('notificacoes_log').select('lancamento_id').eq('id', it.id).maybeSingle()
      const pix = await pixDaFatura(sb, log?.lancamento_id as string)
      if (pix) mensagem += `\n\nPague agora com Pix copia e cola:\n${pix}`
    }
    const r = await enviarTexto(it.instancia, it.numero_destino, mensagem)
    await sb.rpc('registrar_resultado_notificacao', { p_id: it.id, p_ok: r.ok, p_erro: r.erro ?? null, p_resposta: r.resposta ?? null })
    if (r.ok) { enviados++; resultados.push({ id: it.id, destino: mascarar(it.numero_destino), status: 'enviado' }) }
    else { erros++; resultados.push({ id: it.id, destino: mascarar(it.numero_destino), status: 'erro', motivo: r.erro }) }
    await sleep(15000) // 15 s entre mensagens (anti-bloqueio); o cron de 5 em 5 min esvazia a fila

  }
  const resumo = { ok: true, enviados, erros, pulados, resultados }
  console.log('notificacoes-enviar', JSON.stringify({ enviados, erros, pulados }))
  return json(resumo)
})
