import { formatarMes, mesAtualISO, somarMeses } from '../formatos'

/** Navegação por mês com botão de destaque para voltar ao mês atual. */
export function SeletorMes({ mes, aoMudar }: { mes: string; aoMudar: (mes: string) => void }) {
  const atual = mes === mesAtualISO()
  return (
    <div className="inline-flex flex-col items-center gap-1">
      <div className="inline-flex items-center rounded-md border border-line bg-white">
        <button type="button" aria-label="Mês anterior" onClick={() => aoMudar(somarMeses(mes, -1))} className="px-3 py-2 text-ink-muted hover:text-ink">‹</button>
        <span className="min-w-40 whitespace-nowrap text-center text-sm font-medium tabular-nums">{formatarMes(mes)}</span>
        <button type="button" aria-label="Próximo mês" onClick={() => aoMudar(somarMeses(mes, 1))} className="px-3 py-2 text-ink-muted hover:text-ink">›</button>
      </div>
      {/* abaixo do mês (não ao lado) para não parecer parte da navegação */}
      {!atual && <button type="button" onClick={() => aoMudar(mesAtualISO())} className="text-xs font-medium text-brand-700 hover:underline">Voltar ao mês atual</button>}
    </div>
  )
}
