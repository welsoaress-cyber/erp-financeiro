import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { CentrosCustoPage } from './pages/CentrosCustoPage'

/** Centros de custo (etapa 54A): eixo de custo dentro do negócio — departamento, projeto, ponto de rede. */
export const moduloCentrosCusto: DefinicaoModulo = {
  id: 'centros_custo',
  titulo: 'Centros de custo',
  rota: '/centros-custo',
  icone: 'centros',
  Pagina: CentrosCustoPage,
}
