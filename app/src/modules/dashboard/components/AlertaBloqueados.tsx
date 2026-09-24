import { Link } from 'react-router'
import { CartaoRecolhivel } from '../../../core/ui/CartaoRecolhivel'
import { Distintivo } from '../../../core/ui/Distintivo'
import { codigoContrato } from '../../contratos/tipos'
import { useContratos } from '../../contratos/api'
import { usePessoas } from '../../pessoas/api'

interface Props {
  bate: (negocioId: string | null) => boolean
  nomeNegocio: Map<string, string>
}

/** Cartão de clientes suspensos (bloqueados por falta de pagamento) no dashboard geral. Só aparece se houver algum. */
export function AlertaBloqueados({ bate, nomeNegocio }: Props) {
  const contratos = useContratos()
  const pessoas = usePessoas()
  const nomePessoa = new Map((pessoas.data ?? []).map((p) => [p.id, p.nome]))
  const bloqueados = (contratos.data ?? [])
    .filter((c) => c.status === 'suspenso' && c.tipo_financeiro === 'receita' && bate(c.negocio_id))
  if (bloqueados.length === 0) return null
  return (
    <CartaoRecolhivel
      id="clientes-bloqueados"
      titulo={<h2 className="text-sm font-semibold">Clientes bloqueados <Distintivo tom="alerta">{`${bloqueados.length} por falta de pagamento`}</Distintivo></h2>}
      acao={<Link to="/contratos?status=suspenso" className="shrink-0 text-xs font-medium text-brand-600 hover:underline">Ver todos</Link>}
    >
      <ul className="divide-y divide-line">
        {bloqueados.slice(0, 6).map((c) => (
          <li key={c.id} className="px-6 py-3 text-sm">
            <Link to="/contratos?status=suspenso" className="flex items-center justify-between gap-3 hover:underline">
              <span className="min-w-0 truncate">
                <span className="font-medium">{nomePessoa.get(c.pessoa_id) ?? '—'}</span>
                <span className="ml-2 text-xs text-ink-muted">{codigoContrato(c)} · {nomeNegocio.get(c.negocio_id) ?? ''}</span>
              </span>
              <Distintivo tom="alerta">Suspenso</Distintivo>
            </Link>
          </li>
        ))}
      </ul>
      {bloqueados.length > 6 && <p className="px-6 py-2 text-xs text-ink-muted">+ {bloqueados.length - 6} cliente(s) — veja em Contratos.</p>}
    </CartaoRecolhivel>
  )
}
