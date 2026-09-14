import { formatarMes, mesAtualISO, somarMeses } from '../formatos'

/** Navegação por mês com botão de destaque para voltar ao mês atual. */
export function SeletorMes({ mes, aoMudar }: { mes: string; aoMudar: (mes: string) => void }) {
  const atual = mes === mesAtualISO()
  return (
    <div className="relative inline-flex items-center">
      <div className="inline-flex items-center rounded-md border border-line bg-white">
        <button type="button" aria-label="Mês anterior" onClick={() => aoMudar(somarMeses(mes, -1))} className="px-3 py-2 text-ink-muted hover:text-ink">‹</button>
        <span className="min-w-40 whitespace-nowrap text-center text-sm font-medium tabular-nums">{formatarMes(mes)}</span>
        <button type="button" aria-label="Próximo mês" onClick={() => aoMudar(somarMeses(mes, 1))} className="px-3 py-2 text-ink-muted hover:text-ink">›</button>
      </div>
      {/* abaixo do mês, sem ocupar altura (não desalinha os filtros ao lado) */}
      {!atual && <button type="button" onClick={() => aoMudar(mesAtualISO())} className="absolute left-0 right-0 top-full mt-1 text-center text-xs font-medium text-brand-700 hover:underline">Voltar ao mês atual</button>}
    </div>
  )
}
