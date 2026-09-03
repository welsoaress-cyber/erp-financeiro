import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { NotificacoesPage } from './pages/NotificacoesPage'

export const moduloNotificacoes: DefinicaoModulo = {
  id: 'notificacoes',
  titulo: 'Notificações',
  rota: '/notificacoes',
  icone: 'notificacoes',
  Pagina: NotificacoesPage,
}
