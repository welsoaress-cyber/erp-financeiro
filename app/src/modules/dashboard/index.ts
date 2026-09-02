import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { DashboardPage } from './pages/DashboardPage'

export const moduloDashboard: DefinicaoModulo = {
  id: 'dashboard',
  titulo: 'Dashboard',
  rota: '/',
  icone: 'painel',
  Pagina: DashboardPage,
}
