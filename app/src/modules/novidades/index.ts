import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { NovidadesPage } from './pages/NovidadesPage'

export const moduloNovidades: DefinicaoModulo = {
  id: 'novidades',
  titulo: 'Novidades',
  rota: '/novidades',
  icone: 'indicacoes',
  Pagina: NovidadesPage,
}
