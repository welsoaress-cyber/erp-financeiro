import { Link } from 'react-router'
import { CartaoRecolhivel } from '../../../core/ui/CartaoRecolhivel'
import { formatarMoeda } from '../../../core/formatos'
import type { AgendaItem, BucketAgenda } from '../api'

const PERIODOS: { bucket: BucketAgenda; rotulo: string }[] = [
  { bucket: 'hoje', rotulo: 'Hoje' },
  { bucket: '7dias', rotulo: 'Próximos 7 dias' },
  { bucket: '30dias', rotulo: 'Próximos 30 dias' },
  { bucket: 'mais30', rotulo: 'Acima de 30 dias' },
]

interface Props {
  itens: AgendaItem[]
  bate: (negocioId: string | null) => boolean
}

/** Agenda financeira (0125): previstos futuros por faixa de vencimento, A Pagar | A Receber | Saldo Projetado. */
export function AgendaFinanceira({ itens, bate }: Props) {
  const filtrados = itens.filter((i) => bate(i.negocio_id))

  const linhas = PERIODOS.map(({ bucket, rotulo }) => {
    const doPeriodo = filtrados.filter((i) => i.bucket === bucket)
    const aPagar = doPeriodo.filter((i) => i.tipo === 'despesa').reduce((s, i) => s + i.valor, 0)
    const aReceber = doPeriodo.filter((i) => i.tipo === 'receita').reduce((s, i) => s + i.valor, 0)
    return { bucket, rotulo, qtd: doPeriodo.length, aPagar, aReceber, saldo: aReceber - aPagar }
  })

  return (
    <CartaoRecolhivel
      id="agenda-financeira"
      titulo={<h2 className="text-sm font-semibold">Agenda financeira</h2>}
      acao={<Link to="/financeiro/lancamentos" className="shrink-0 text-xs font-medium text-brand-600 hover:underline">Ver lançamentos</Link>}
      recolhidoPadrao={false}
    >
      <ul className="divide-y divide-line">
        {linhas.map((l) => (
          <li key={l.bucket}>
            <Link to="/financeiro/lancamentos" className="grid grid-cols-2 gap-2 px-6 py-3 hover:bg-surface sm:grid-cols-4 sm:items-center">
              <span>
                <span className="text-sm font-semibold">{l.rotulo}</span>
                <span className="block text-xs text-ink-muted">{l.qtd} lançamento(s)</span>
              </span>
              <span className="text-right sm:text-right">
                <span className="block text-xs font-medium text-ink-muted">A pagar</span>
                <span className="text-sm font-semibold tabular-nums text-red-700">{formatarMoeda(l.aPagar)}</span>
              </span>
              <span className="text-right">
                <span className="block text-xs font-medium text-ink-muted">A receber</span>
                <span className="text-sm font-semibold tabular-nums text-green-700">{formatarMoeda(l.aReceber)}</span>
              </span>
              <span className="text-right">
                <span className="block text-xs font-medium text-ink-muted">Saldo projetado</span>
                <span className={`text-sm font-semibold tabular-nums ${l.saldo < 0 ? 'text-red-700' : 'text-green-700'}`}>{formatarMoeda(l.saldo)}</span>
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </CartaoRecolhivel>
  )
}
