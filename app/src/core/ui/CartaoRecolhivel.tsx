import { useState, type ReactNode } from 'react'
import { Cartao } from './Cartao'

const CHAVE = 'erp.dash.recolhido.'

function lerRecolhido(id: string, padrao: boolean): boolean {
  try {
    const v = localStorage.getItem(CHAVE + id)
    return v === null ? padrao : v === '1'
  } catch {
    return padrao
  }
}

/** Cartão com cabeçalho clicável para recolher/expandir o conteúdo; a escolha fica salva no navegador. */
export function CartaoRecolhivel({ id, titulo, acao, recolhidoPadrao = true, children }: {
  id: string
  titulo: ReactNode
  acao?: ReactNode
  recolhidoPadrao?: boolean
  children: ReactNode
}) {
  const [recolhido, setRecolhido] = useState(() => lerRecolhido(id, recolhidoPadrao))

  function alternar() {
    setRecolhido((v) => {
      try {
        localStorage.setItem(CHAVE + id, v ? '0' : '1')
      } catch {
        // sem storage — vale só até recarregar
      }
      return !v
    })
  }

  return (
    <Cartao className="p-0">
      <div className={`flex items-center justify-between gap-3 px-6 py-3 ${recolhido ? '' : 'border-b border-line'}`}>
        <button type="button" onClick={alternar} aria-expanded={!recolhido} className="flex min-w-0 items-center gap-2 text-left">
          <span className={`text-xs text-ink-muted transition-transform ${recolhido ? '' : 'rotate-90'}`}>▶</span>
          {titulo}
        </button>
        {acao}
      </div>
      {!recolhido && children}
    </Cartao>
  )
}
