import { Link } from 'react-router'
import { CartaoRecolhivel } from '../../../core/ui/CartaoRecolhivel'
import { formatarMoedaOuOculto, hojeISO } from '../../../core/formatos'
import { useLancamentosVencidosAntes } from '../../lancamentos/api'
import { useContratos } from '../../contratos/api'
import { usePedidos } from '../../compras/api'
import { useEstoqueItens, useItensComEntrada } from '../../estoque/api'
import { statusItem } from '../../estoque/tipos'
import { useNegocios } from '../../negocios/api'
import { useSaudeNotificacoes } from '../api'

interface Props {
  bate: (negocioId: string | null) => boolean
  oculto: boolean
}

function CartaoPendencia({ to, titulo, quantidade, detalhe }: { to: string; titulo: string; quantidade: number; detalhe: string }) {
  const tom = quantidade === 0 ? 'text-green-700 bg-green-50' : quantidade >= 10 ? 'text-red-700 bg-red-50' : 'text-amber-800 bg-amber-50'
  return (
    <Link to={to} className="flex flex-col gap-2 rounded-lg border border-line bg-white p-4 hover:border-ink-muted">
      <span className="flex items-center justify-between gap-2">
        <span className="text-sm font-semibold">{titulo}</span>
        <span className={`inline-flex min-w-[1.75rem] justify-center rounded-full px-2 py-0.5 text-sm font-bold ${tom}`}>{quantidade}</span>
      </span>
      <span className="text-xs text-ink-muted">{detalhe}</span>
    </Link>
  )
}

/** Pendências operacionais (0126): tudo que precisa de ação agora, de relance. */
export function PendenciasOperacionais({ bate, oculto }: Props) {
  const hoje = hojeISO()
  const vencidasPagar = useLancamentosVencidosAntes('despesa', hoje)
  const vencidasReceber = useLancamentosVencidosAntes('receita', hoje)
  const contratos = useContratos()
  const pedidos = usePedidos()
  const negocios = useNegocios()
  const itensEstoque = useEstoqueItens()
  const comEntrada = useItensComEntrada()
  const saudeNotificacoes = useSaudeNotificacoes()

  const pagarFiltradas = (vencidasPagar.data ?? []).filter((l) => bate(l.negocio_id))
  const receberFiltradas = (vencidasReceber.data ?? []).filter((l) => bate(l.negocio_id))
  const bloqueados = (contratos.data ?? []).filter((c) => c.status === 'suspenso' && c.tipo_financeiro === 'receita' && bate(c.negocio_id))
  const pedidosAbertos = (pedidos.data ?? []).filter((p) => (p.status === 'aberto' || p.status === 'recebido_parcial') && bate(p.negocio_id))
  const estoqueAlerta = (itensEstoque.data ?? [])
    .filter((i) => i.ativo && bate(i.negocio_id))
    .map((i) => statusItem(i, (comEntrada.data ?? new Set()).has(i.id)))
    .filter((st) => st.tom === 'zerado' || st.tom === 'baixo')

  const ativos = (negocios.data ?? []).filter((n) => n.ativo && bate(n.id))
  const avisosAcao = ativos.filter((n) => {
    const cfg = saudeNotificacoes.data?.configs.find((c) => c.negocio_id === n.id)
    const log = (saudeNotificacoes.data?.log ?? []).filter((l) => l.negocio_id === n.id)
    const erros24h = log.filter((l) => l.status === 'erro' && Date.now() - new Date(l.criado_em).getTime() < 86_400_000).length
    const pendentesAntigos = log.filter((l) => l.status === 'pendente' && Date.now() - new Date(l.criado_em).getTime() > 86_400_000).length
    return !cfg || !cfg.ativo || erros24h > 0 || pendentesAntigos > 0
  }).length

  const somar = (xs: { valor: number }[]) => xs.reduce((s, l) => s + l.valor, 0)

  return (
    <CartaoRecolhivel
      id="pendencias-operacionais"
      titulo={<h2 className="text-sm font-semibold">Pendências</h2>}
      recolhidoPadrao={false}
    >
      <div className="grid gap-3 p-4 sm:grid-cols-2 lg:grid-cols-3">
        <CartaoPendencia to="/financeiro/pagar" titulo="Contas a pagar vencidas" quantidade={pagarFiltradas.length}
          detalhe={`Total em aberto ${formatarMoedaOuOculto(somar(pagarFiltradas), oculto)}`} />
        <CartaoPendencia to="/financeiro/receber" titulo="Contas a receber vencidas" quantidade={receberFiltradas.length}
          detalhe={`Total em aberto ${formatarMoedaOuOculto(somar(receberFiltradas), oculto)}`} />
        <CartaoPendencia to="/contratos?status=suspenso" titulo="Clientes bloqueados" quantidade={bloqueados.length}
          detalhe="Por inadimplência, acesso cortado" />
        <CartaoPendencia to="/compras/pedidos" titulo="Compras aguardando recebimento" quantidade={pedidosAbertos.length}
          detalhe="Pedidos em aberto no fornecedor" />
        <CartaoPendencia to="/notificacoes" titulo="Avisos pendentes" quantidade={avisosAcao}
          detalhe="Negócio(s) com ação necessária no WhatsApp" />
        <CartaoPendencia to="/estoque" titulo="Estoque em alerta" quantidade={estoqueAlerta.length}
          detalhe="Itens zerados ou abaixo do mínimo" />
      </div>
    </CartaoRecolhivel>
  )
}
