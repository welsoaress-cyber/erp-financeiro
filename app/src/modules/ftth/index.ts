import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { FtthPage } from './pages/FtthPage'

export const moduloFtth: DefinicaoModulo = {
  id: 'ftth',
  titulo: 'Rede FTTH',
  rota: '/ftth',
  icone: 'ftth',
  Pagina: FtthPage,
}
