import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { ContratosPage } from './pages/ContratosPage'

export const moduloContratos: DefinicaoModulo = {
  id: 'contratos',
  titulo: 'Contratos',
  rota: '/contratos',
  icone: 'contratos',
  Pagina: ContratosPage,
}
