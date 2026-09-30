import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { PessoasPage } from './pages/PessoasPage'

export const moduloPessoas: DefinicaoModulo = {
  id: 'pessoas',
  titulo: 'Pessoas',
  rota: '/pessoas',
  icone: 'pessoas',
  Pagina: PessoasPage,
}

/** Atalho: mesma tela de Pessoas, acessível também por Suprimentos → Fornecedores. */
export const moduloFornecedores: DefinicaoModulo = {
  id: 'fornecedores',
  titulo: 'Fornecedores',
  rota: '/fornecedores',
  icone: 'pessoas',
  Pagina: PessoasPage,
}
