import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { CategoriasPage } from './pages/CategoriasPage'

export const moduloCategorias: DefinicaoModulo = {
  id: 'categorias',
  titulo: 'Categorias',
  rota: '/categorias',
  icone: 'categorias',
  Pagina: CategoriasPage,
}
