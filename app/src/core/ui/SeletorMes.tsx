import { formatarMes, somarMeses } from '../formatos'

export function SeletorMes({ mes, aoMudar }: { mes: string; aoMudar: (mes: string) => void }) {
  return (
    <div className="inline-flex items-center rounded-md border border-line bg-white">
      <button type="button" aria-label="Mês anterior" onClick={() => aoMudar(somarMeses(mes, -1))} className="px-3 py-2 text-ink-muted hover:text-ink">‹</button>
      <span className="min-w-40 text-center text-sm font-medium tabular-nums">{formatarMes(mes)}</span>
      <button type="button" aria-label="Próximo mês" onClick={() => aoMudar(somarMeses(mes, 1))} className="px-3 py-2 text-ink-muted hover:text-ink">›</button>
    </div>
  )
}
