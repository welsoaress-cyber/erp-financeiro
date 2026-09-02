import { useId, type SelectHTMLAttributes } from 'react'

interface Props extends SelectHTMLAttributes<HTMLSelectElement> {
  rotulo: string
  opcoes: ReadonlyArray<{ valor: string; rotulo: string }>
  ajuda?: string
}

export function Selecao({ rotulo, opcoes, ajuda, className = '', id, ...rest }: Props) {
  const gerado = useId()
  const selectId = id ?? gerado
  return (
    <div className="space-y-1">
      <label htmlFor={selectId} className="block text-sm font-medium text-ink">{rotulo}</label>
      <select
        id={selectId}
        {...rest}
        className={`h-10 w-full rounded-md border border-line bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-2 focus:ring-brand-100 disabled:cursor-not-allowed disabled:bg-surface disabled:text-ink-muted ${className}`}
      >
        {opcoes.map((o) => <option key={o.valor} value={o.valor}>{o.rotulo}</option>)}
      </select>
      {ajuda && <p className="text-xs text-ink-muted">{ajuda}</p>}
    </div>
  )
}
