import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { AppsPage } from './pages/AppsPage'

export const moduloApps: DefinicaoModulo = {
  id: 'apps',
  titulo: 'Apps',
  rota: '/apps',
  icone: 'apps',
  Pagina: AppsPage,
}
