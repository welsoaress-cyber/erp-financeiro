import { Link } from 'react-router'
import { Cartao } from '../../../core/ui/Cartao'
import { useContratos } from '../../contratos/api'

/** Contagem de contratos de receita bloqueados/desbloqueados no dashboard geral, clicável — leva pra Contratos já filtrado. */
export function StatusPessoas() {
  const contratos = useContratos()
  const receita = (contratos.data ?? []).filter((c) => c.tipo_financeiro === 'receita')
  const bloqueadas = receita.filter((c) => c.status === 'suspenso').length
  const desbloqueadas = receita.filter((c) => c.status === 'ativo').length
  return (
    <Cartao className="p-5">
      <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">Clientes</p>
      <div className="mt-2 flex items-center gap-5">
        <Link to="/contratos?status=suspenso" className="hover:underline">
          <span className="text-2xl font-semibold tabular-nums text-red-700">{bloqueadas}</span>
          <span className="ml-1 text-xs text-ink-muted">bloqueadas</span>
        </Link>
        <Link to="/contratos?status=ativo" className="hover:underline">
          <span className="text-2xl font-semibold tabular-nums text-green-700">{desbloqueadas}</span>
          <span className="ml-1 text-xs text-ink-muted">desbloqueadas</span>
        </Link>
      </div>
    </Cartao>
  )
}
