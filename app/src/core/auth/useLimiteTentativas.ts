import { useCallback, useEffect, useState } from 'react'

/** Faixas de bloqueio por número de falhas seguidas. */
const FAIXAS: ReadonlyArray<{ apartirDe: number; minutos: number }> = [
  { apartirDe: 10, minutos: 15 },
  { apartirDe: 5, minutos: 5 },
  { apartirDe: 3, minutos: 1 },
]
const PAUSA_CURTA_MS = 5_000
const ESQUECER_APOS_MS = 60 * 60_000 // sem novas falhas por 1 h, o contador zera
const CHAVE = 'erp.login.tentativas'

interface Estado { count: number; ultimaFalha: number; liberadoEm: number }
const VAZIO: Estado = { count: 0, ultimaFalha: 0, liberadoEm: 0 }

function ler(): Estado {
  try {
    const bruto = localStorage.getItem(CHAVE)
    if (!bruto) return VAZIO
    const e = JSON.parse(bruto) as Estado
    return Date.now() - e.ultimaFalha > ESQUECER_APOS_MS ? VAZIO : e
  } catch { return VAZIO }
}

function gravar(estado: Estado) {
  try { localStorage.setItem(CHAVE, JSON.stringify(estado)) } catch { /* ignora */ }
}

function duracaoBloqueio(count: number): number {
  const faixa = FAIXAS.find((f) => count >= f.apartirDe)
  return faixa ? faixa.minutos * 60_000 : PAUSA_CURTA_MS
}

/**
 * Freio de tentativas de login no navegador (experiência do usuário, não
 * segurança): 5 s após cada falha; 1 min a partir de 3 falhas; 5 min a partir
 * de 5; 15 min a partir de 10. Persiste em localStorage. A proteção real contra
 * força bruta é o rate limiting do Supabase Auth.
 */
export function useLimiteTentativas() {
  const [estado, setEstado] = useState<Estado>(ler)
  const [agora, setAgora] = useState(() => Date.now())

  const bloqueado = estado.liberadoEm > agora
  const segundosRestantes = bloqueado ? Math.ceil((estado.liberadoEm - agora) / 1000) : 0

  useEffect(() => {
    if (!bloqueado) return
    const id = window.setInterval(() => setAgora(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [bloqueado])

  const registrarFalha = useCallback(() => {
    const atual = ler()
    const count = atual.count + 1
    const novo = { count, ultimaFalha: Date.now(), liberadoEm: Date.now() + duracaoBloqueio(count) }
    gravar(novo)
    setEstado(novo)
    setAgora(Date.now())
  }, [])

  const registrarSucesso = useCallback(() => {
    gravar(VAZIO)
    setEstado(VAZIO)
  }, [])

  const mensagem = !bloqueado ? null
    : segundosRestantes > 60 ? `Muitas tentativas. Aguarde ${Math.ceil(segundosRestantes / 60)} minutos.`
    : segundosRestantes > 10 ? `Muitas tentativas. Aguarde 1 minuto.`
    : `Aguarde ${segundosRestantes} s para tentar novamente.`

  return { bloqueado, mensagem, tentativas: estado.count, registrarFalha, registrarSucesso }
}
