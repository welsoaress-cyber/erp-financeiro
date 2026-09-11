import { Link } from 'react-router'
import { CartaoRecolhivel } from '../../../core/ui/CartaoRecolhivel'
import { Distintivo } from '../../../core/ui/Distintivo'
import { useEstoqueItens } from '../../estoque/api'
import { fmtQtd, statusItem } from '../../estoque/tipos'

interface Props {
  bate: (negocioId: string | null) => boolean
  nomeNegocio: Map<string, string>
}

/** Cartão de alertas de estoque no dashboard geral: itens zerados ou abaixo do mínimo. Só aparece se houver alerta. */
export function AlertasEstoque({ bate, nomeNegocio }: Props) {
  const itens = useEstoqueItens()
  const alertas = (itens.data ?? [])
    .filter((i) => i.ativo && bate(i.negocio_id))
    .map((i) => ({ item: i, st: statusItem(i) }))
    .filter((x) => x.st.tom === 'zerado' || x.st.tom === 'baixo')
    .sort((a, b) => (a.st.tom === b.st.tom ? 0 : a.st.tom === 'zerado' ? -1 : 1))
  if (alertas.length === 0) return null
  return (
    <CartaoRecolhivel
      id="estoque"
      titulo={<h2 className="text-sm font-semibold">Estoque <Distintivo tom="alerta">{`${alertas.length} item(ns) em alerta`}</Distintivo></h2>}
      acao={<Link to="/estoque" className="shrink-0 text-xs font-medium text-brand-600 hover:underline">Abrir estoque</Link>}
    >
      <ul className="divide-y divide-line">
        {alertas.slice(0, 6).map(({ item, st }) => (
          <li key={item.id} className="flex items-center justify-between gap-3 px-6 py-3 text-sm">
            <span className="min-w-0 truncate">
              <span className="font-medium">{item.codigo} · {item.nome}</span>
              <span className="ml-2 text-xs text-ink-muted">{nomeNegocio.get(item.negocio_id) ?? ''} · {fmtQtd(item.quantidade_atual)} {item.unidade_medida}{item.quantidade_minima > 0 ? ` (mín. ${fmtQtd(item.quantidade_minima)})` : ''}</span>
            </span>
            <Distintivo tom="alerta">{st.rotulo}</Distintivo>
          </li>
        ))}
        {alertas.length > 6 && <li className="px-6 py-2 text-xs text-ink-muted">+ {alertas.length - 6} item(ns) — veja no módulo Estoque.</li>}
      </ul>
    </CartaoRecolhivel>
  )
}
