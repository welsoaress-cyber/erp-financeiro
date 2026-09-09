import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { DisparosPage } from './pages/DisparosPage'

export const moduloDisparos: DefinicaoModulo = {
  id: 'disparos',
  titulo: 'Disparos',
  rota: '/disparos',
  icone: 'disparos',
  Pagina: DisparosPage,
}
