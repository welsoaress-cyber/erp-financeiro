import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { NegociosPage } from './pages/NegociosPage'

export const moduloNegocios: DefinicaoModulo = {
  id: 'negocios',
  titulo: 'Negócios',
  rota: '/negocios',
  icone: 'negocios',
  Pagina: NegociosPage,
}
