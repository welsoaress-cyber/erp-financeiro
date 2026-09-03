import { Cartao } from '../../core/ui/Cartao'

export function Indicador({ rotulo, valor, tom }: { rotulo: string; valor: string; tom?: 'alerta' }) {
  return <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">{rotulo}</p><p className={`mt-1 text-xl font-semibold tabular-nums ${tom === 'alerta' ? 'text-red-700' : ''}`}>{valor}</p></Cartao>
}
export function Titulo({ children, acao }: { children: string; acao?: React.ReactNode }) {
  return <div className="mb-4 flex items-center justify-between"><h1 className="text-xl font-semibold">{children}</h1>{acao}</div>
}

