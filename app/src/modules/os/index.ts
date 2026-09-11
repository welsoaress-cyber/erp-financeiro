import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { OsPage } from './pages/OsPage'

export const moduloOs: DefinicaoModulo = {
  id: 'os',
  titulo: 'Ordens de Serviço',
  rota: '/os',
  icone: 'os',
  Pagina: OsPage,
}
