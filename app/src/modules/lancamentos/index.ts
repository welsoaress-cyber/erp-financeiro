import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { LancamentosPage } from './pages/LancamentosPage'

export const moduloLancamentos: DefinicaoModulo = {
  id: 'lancamentos',
  titulo: 'Lançamentos',
  rota: '/lancamentos',
  icone: 'lancamentos',
  Pagina: LancamentosPage,
}
