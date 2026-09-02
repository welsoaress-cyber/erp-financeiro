import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { PessoasPage } from './pages/PessoasPage'

export const moduloPessoas: DefinicaoModulo = {
  id: 'pessoas',
  titulo: 'Pessoas',
  rota: '/pessoas',
  icone: 'pessoas',
  Pagina: PessoasPage,
}
