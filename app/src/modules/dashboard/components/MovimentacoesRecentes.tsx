import { Link } from 'react-router'
import { CartaoRecolhivel } from '../../../core/ui/CartaoRecolhivel'
import { formatarData, formatarMoeda } from '../../../core/formatos'
import { ROTULO_TIPO } from '../../lancamentos/tipos'
import { ROTULO_PESSOAL } from '../../negocios/tipos'
import type { Lancamento } from '../../lancamentos/tipos'

interface Props {
  lancamentos: Lancamento[]
  nomeConta: Map<string, string>
  nomeCategoria: Map<string, string>
  nomeNegocio: Map<string, string>
}

/** Últimas movimentações efetivadas: data, descrição, valor, conta, status. */
export function MovimentacoesRecentes({ lancamentos, nomeConta, nomeCategoria, nomeNegocio }: Props) {
  const rotuloNegocio = (id: string | null) => (id ? nomeNegocio.get(id) ?? '—' : ROTULO_PESSOAL)
  return (
    <CartaoRecolhivel
      id="movimentacoes-recentes"
      titulo={<h2 className="text-sm font-semibold">Movimentações recentes</h2>}
      acao={<Link to="/financeiro/lancamentos" className="shrink-0 text-xs font-medium text-brand-600 hover:underline">Ver todas</Link>}
      recolhidoPadrao={false}
    >
      {lancamentos.length === 0 ? (
        <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhum lançamento efetivado ainda.</p>
      ) : (
        <ul className="divide-y divide-line">
          {lancamentos.map((l) => (
            <li key={l.id} className="flex items-center justify-between gap-3 px-6 py-3 text-sm">
              <div className="min-w-0">
                <p className="truncate font-medium">{l.descricao}</p>
                <p className="truncate text-xs text-ink-muted">
                  {formatarData(l.data_efetivacao ?? l.data_competencia)} · {l.tipo === 'transferencia' ? `${nomeConta.get(l.conta_id) ?? '—'} → ${nomeConta.get(l.conta_destino_id ?? '') ?? '—'}` : `${nomeCategoria.get(l.categoria_id ?? '') ?? ROTULO_TIPO[l.tipo]} · ${nomeConta.get(l.conta_id) ?? '—'}`}{l.negocio_id ? ` · ${rotuloNegocio(l.negocio_id)}` : ''}
                </p>
              </div>
              <span className={`shrink-0 font-medium tabular-nums ${l.tipo === 'receita' ? 'text-green-700' : l.tipo === 'despesa' ? 'text-red-700' : 'text-brand-700'}`}>
                {l.tipo === 'despesa' ? '− ' : l.tipo === 'receita' ? '+ ' : ''}{formatarMoeda(l.valor)}
              </span>
            </li>
          ))}
        </ul>
      )}
    </CartaoRecolhivel>
  )
}
