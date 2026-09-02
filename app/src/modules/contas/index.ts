import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { ContasPage } from './pages/ContasPage'

export const moduloContas: DefinicaoModulo = {
  id: 'contas',
  titulo: 'Contas',
  rota: '/contas',
  icone: 'contas',
  Pagina: ContasPage,
}
