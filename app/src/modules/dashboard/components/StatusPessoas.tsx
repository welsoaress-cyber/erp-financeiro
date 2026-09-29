import { Link } from 'react-router'
import { Cartao } from '../../../core/ui/Cartao'
import { usePessoas } from '../../pessoas/api'

/** Contagem de pessoas ativas/inativas no dashboard geral, clicável — leva pra Pessoas já filtrado. */
export function StatusPessoas() {
  const pessoas = usePessoas()
  const ativas = (pessoas.data ?? []).filter((p) => p.ativo).length
  const inativas = (pessoas.data ?? []).filter((p) => !p.ativo).length
  return (
    <Cartao className="p-5">
      <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">Pessoas</p>
      <div className="mt-2 flex items-center gap-5">
        <Link to="/pessoas" className="hover:underline">
          <span className="text-2xl font-semibold tabular-nums text-green-700">{ativas}</span>
          <span className="ml-1 text-xs text-ink-muted">ativas</span>
        </Link>
        <Link to="/pessoas?inativas=1" className="hover:underline">
          <span className="text-2xl font-semibold tabular-nums text-ink-muted">{inativas}</span>
          <span className="ml-1 text-xs text-ink-muted">inativas</span>
        </Link>
      </div>
    </Cartao>
  )
}
