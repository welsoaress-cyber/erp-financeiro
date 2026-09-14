import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { RelatoriosPage } from './pages/RelatoriosPage'
import { RelatorioPage } from './pages/RelatorioPage'

/** Central de Relatórios (etapa 53): catálogo em `catalogo.ts`, uma view por relatório. */
export const moduloRelatorios: DefinicaoModulo = {
  id: 'relatorios',
  titulo: 'Relatórios',
  rota: '/relatorios',
  icone: 'relatorios',
  Pagina: RelatoriosPage,
  subRotas: [{ rota: '/relatorios/:id', Pagina: RelatorioPage }],
}
