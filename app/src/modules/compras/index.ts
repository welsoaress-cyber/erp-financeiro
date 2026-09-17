import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { ComprasPage } from './pages/ComprasPage'

export const moduloCompras: DefinicaoModulo = {
  id: 'compras',
  titulo: 'Compras',
  rota: '/compras',
  icone: 'compras',
  Pagina: ComprasPage,
}
