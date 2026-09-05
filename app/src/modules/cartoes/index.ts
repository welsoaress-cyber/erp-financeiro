import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { CartoesPage } from './pages/CartoesPage'

export const moduloCartoes: DefinicaoModulo = {
  id: 'cartoes',
  titulo: 'Cartões',
  rota: '/cartoes',
  icone: 'cartao',
  Pagina: CartoesPage,
}
