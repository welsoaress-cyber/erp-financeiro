import type { ReactNode } from 'react'

/**
 * Barra de filtros padrão das listas: busca à esquerda, selects ao lado, contador/extras à direita.
 * Nasceu para padronizar as telas depois que várias listas grandes ficaram só com busca de texto.
 */
export function BarraFiltros({ children }: { children: ReactNode }) {
  return <div className="flex flex-wrap items-center gap-2 border-b border-line px-4 py-3 text-sm sm:px-6">{children}</div>
}

export function CampoBusca({ valor, aoMudar, rotulo, className = '' }: { valor: string; aoMudar: (v: string) => void; rotulo: string; className?: string }) {
  return (
    <input
      type="search"
      aria-label={rotulo}
      placeholder={rotulo}
      value={valor}
      onChange={(e) => aoMudar(e.target.value)}
      className={`h-9 w-full max-w-xs rounded-md border border-line bg-white px-3 text-sm outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-100 ${className}`}
    />
  )
}

export function SelectFiltro({ valor, aoMudar, rotulo, children }: { valor: string; aoMudar: (v: string) => void; rotulo: string; children: ReactNode }) {
  return (
    <select aria-label={rotulo} value={valor} onChange={(e) => aoMudar(e.target.value)} className="h-9 rounded-md border border-line bg-white px-2 text-sm">
      {children}
    </select>
  )
}

/** Contador "N de M" — some quando nada está filtrado para não poluir. */
export function ContagemFiltro({ visiveis, total, singular, plural }: { visiveis: number; total: number; singular: string; plural: string }) {
  const rotulo = visiveis === 1 ? singular : plural
  return <span className="text-ink-muted">{visiveis === total ? `${total} ${rotulo}` : `${visiveis} de ${total} ${plural}`}</span>
}
