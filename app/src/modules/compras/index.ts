import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { ComprasPage } from './pages/ComprasPage'

export const moduloComprasRequisicoes: DefinicaoModulo = { id: 'compras_requisicoes', titulo: 'Requisições', rota: '/compras/requisicoes', icone: 'compras', Pagina: ComprasPage }
export const moduloComprasPedidos: DefinicaoModulo = { id: 'compras_pedidos', titulo: 'Pedidos de Compra', rota: '/compras/pedidos', icone: 'compras', Pagina: ComprasPage }
export const moduloComprasRecebimento: DefinicaoModulo = { id: 'compras_recebimento', titulo: 'Recebimento', rota: '/compras/recebimento', icone: 'compras', Pagina: ComprasPage }
