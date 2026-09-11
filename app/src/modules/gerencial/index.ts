import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { GerencialPage } from './pages/GerencialPage'

export const moduloGerencial: DefinicaoModulo = {
  id: 'gerencial',
  titulo: 'Gerencial',
  rota: '/gerencial',
  icone: 'gerencial',
  Pagina: GerencialPage,
}
