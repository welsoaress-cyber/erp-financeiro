import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { ConfiguracoesPage } from './pages/ConfiguracoesPage'
import { ImportarCsvPage } from './importacao/ImportarCsvPage'

export const moduloConfiguracoes: DefinicaoModulo = {
  id: 'configuracoes',
  titulo: 'Configurações',
  rota: '/configuracoes',
  icone: 'configuracoes',
  Pagina: ConfiguracoesPage,
  subRotas: [{ rota: '/configuracoes/importar', Pagina: ImportarCsvPage }],
}
