import { Children, isValidElement, type ReactNode } from 'react'

const linha = 'flex flex-wrap items-center gap-2 border-b border-line px-4 py-3 text-sm sm:px-6'

/**
 * Barra de filtros padrão das listas: busca (+ contador) numa linha própria no topo, sozinha,
 * e o resto dos filtros (selects, seletor de mês…) numa linha abaixo. Divide sozinho pelo tipo
 * do filho — nenhuma tela precisa se preocupar com isso, só listar os filtros como children.
 */
export function BarraFiltros({ children }: { children: ReactNode }) {
  const filhos = Children.toArray(children)
  const daBusca = (c: ReactNode) => isValidElement(c) && (c.type === CampoBusca || c.type === ContagemFiltro)
  const busca = filhos.filter(daBusca)
  const resto = filhos.filter((c) => !daBusca(c))
  if (busca.length === 0) return <div className={linha}>{children}</div>
  return (
    <>
      <div className={linha}>{busca}</div>
      {resto.length > 0 && <div className={linha}>{resto}</div>}
    </>
  )
}

export function CampoBusca({ valor, aoMudar, rotulo, className = '' }: { valor: string; aoMudar: (v: string) => void; rotulo: string; className?: string }) {
  return (
    <input
      type="search"
      aria-label={rotulo}
      placeholder={rotulo}
      value={valor}
      onChange={(e) => aoMudar(e.target.value)}
      className={`h-9 w-full max-w-none flex-1 rounded-md border border-line bg-white px-3 text-sm outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-100 ${className}`}
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
