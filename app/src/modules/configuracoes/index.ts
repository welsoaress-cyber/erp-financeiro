import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { ConfiguracoesPage } from './pages/ConfiguracoesPage'

export const moduloConfiguracoes: DefinicaoModulo = {
  id: 'configuracoes',
  titulo: 'Configurações',
  rota: '/configuracoes',
  icone: 'configuracoes',
  Pagina: ConfiguracoesPage,
}
