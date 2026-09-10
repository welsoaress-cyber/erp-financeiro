import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { EstoquePage } from './pages/EstoquePage'

export const moduloEstoque: DefinicaoModulo = {
  id: 'estoque',
  titulo: 'Estoque',
  rota: '/estoque',
  icone: 'estoque',
  Pagina: EstoquePage,
}
