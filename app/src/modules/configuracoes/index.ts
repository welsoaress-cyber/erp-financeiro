import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { ConfiguracoesPage } from './pages/ConfiguracoesPage'
import { ImportarCsvPage } from './importacao/ImportarCsvPage'
import { IntegracoesPage } from './integracoes/IntegracoesPage'

export const moduloConfiguracoes: DefinicaoModulo = {
  id: 'configuracoes',
  titulo: 'Configurações',
  rota: '/configuracoes',
  icone: 'configuracoes',
  Pagina: ConfiguracoesPage,
  subRotas: [
    { rota: '/configuracoes/importar', Pagina: ImportarCsvPage },
    { rota: '/configuracoes/integracoes', Pagina: IntegracoesPage },
  ],
}
