import { useCallback, useEffect, useState } from 'react'

const MAX_TENTATIVAS = 5
const PAUSA_APOS_FALHA_MS = 5_000
const BLOQUEIO_MS = 5 * 60_000
const CHAVE = 'erp.login.tentativas'

interface Estado { tentativas: number; liberadoEm: number }

function ler(): Estado {
  try {
    const bruto = sessionStorage.getItem(CHAVE)
    if (bruto) return JSON.parse(bruto) as Estado
  } catch { /* armazenamento indisponível: segue só em memória */ }
  return { tentativas: 0, liberadoEm: 0 }
}

function gravar(estado: Estado) {
  try { sessionStorage.setItem(CHAVE, JSON.stringify(estado)) } catch { /* ignora */ }
}

/**
 * Freio de tentativas de login no navegador (camada de experiência, não de
 * segurança): 5 s de pausa após cada falha e 5 min após 5 falhas seguidas.
 * A proteção real contra força bruta é o rate limiting do Supabase Auth.
 */
export function useLimiteTentativas() {
  const [estado, setEstado] = useState<Estado>(ler)
  const [agora, setAgora] = useState(() => Date.now())

  const bloqueadoAte = estado.liberadoEm
  const bloqueado = bloqueadoAte > agora
  const segundosRestantes = bloqueado ? Math.ceil((bloqueadoAte - agora) / 1000) : 0

  useEffect(() => {
    if (!bloqueado) return
    const id = window.setInterval(() => setAgora(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [bloqueado])

  const registrarFalha = useCallback(() => {
    setEstado((atual) => {
      const tentativas = atual.tentativas + 1
      const liberadoEm = Date.now() + (tentativas >= MAX_TENTATIVAS ? BLOQUEIO_MS : PAUSA_APOS_FALHA_MS)
      const novo = { tentativas: tentativas >= MAX_TENTATIVAS ? 0 : tentativas, liberadoEm }
      gravar(novo)
      return novo
    })
    setAgora(Date.now())
  }, [])

  const registrarSucesso = useCallback(() => {
    const novo = { tentativas: 0, liberadoEm: 0 }
    gravar(novo)
    setEstado(novo)
  }, [])

  const mensagem = !bloqueado ? null
    : segundosRestantes > 60 ? `Muitas tentativas. Aguarde ${Math.ceil(segundosRestantes / 60)} minutos.`
    : `Aguarde ${segundosRestantes} s para tentar novamente.`

  return { bloqueado, mensagem, registrarFalha, registrarSucesso }
}
