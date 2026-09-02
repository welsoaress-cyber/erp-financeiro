import { useEffect } from 'react'

export const INATIVIDADE_MS = 30 * 60_000
export const CHAVE_ULTIMA_ATIVIDADE = 'erp.ultima_atividade'
export const CHAVE_SESSAO_EXPIRADA = 'erp.sessao_expirada'
const EVENTOS = ['mousemove', 'keydown', 'click', 'scroll', 'touchstart'] as const

/**
 * Encerra a sessão após 30 min sem interação. Guarda a última atividade em
 * localStorage para valer entre abas e após fechar/reabrir o navegador.
 */
export function useInatividade(aoExpirar: () => void) {
  useEffect(() => {
    let timer = 0
    let ultimoRegistro = 0

    const expirar = () => {
      try { sessionStorage.setItem(CHAVE_SESSAO_EXPIRADA, '1'); localStorage.removeItem(CHAVE_ULTIMA_ATIVIDADE) } catch { /* ignora */ }
      aoExpirar()
    }
    const agendar = (ms: number) => {
      window.clearTimeout(timer)
      timer = window.setTimeout(expirar, ms)
    }
    const atividade = () => {
      const agora = Date.now()
      if (agora - ultimoRegistro < 1000) return // no máximo 1 gravação por segundo
      ultimoRegistro = agora
      try { localStorage.setItem(CHAVE_ULTIMA_ATIVIDADE, String(agora)) } catch { /* ignora */ }
      agendar(INATIVIDADE_MS)
    }

    // Ao montar: se a última atividade conhecida é antiga demais, expira já.
    let ultima = 0
    try { ultima = Number(localStorage.getItem(CHAVE_ULTIMA_ATIVIDADE) ?? 0) } catch { /* ignora */ }
    if (ultima && Date.now() - ultima >= INATIVIDADE_MS) { expirar(); return }
    atividade()

    EVENTOS.forEach((e) => window.addEventListener(e, atividade, { passive: true }))
    return () => {
      window.clearTimeout(timer)
      EVENTOS.forEach((e) => window.removeEventListener(e, atividade))
    }
  }, [aoExpirar])
}
