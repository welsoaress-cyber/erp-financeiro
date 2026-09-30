import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { RhPage } from './pages/RhPage'
import { PontoPage } from './pages/PontoPage'
import { FeriasPage } from './pages/FeriasPage'

export const moduloRh: DefinicaoModulo = { id: 'rh', titulo: 'Funcionários', rota: '/rh', icone: 'rh', Pagina: RhPage }
export const moduloRhPonto: DefinicaoModulo = { id: 'rh_ponto', titulo: 'Ponto', rota: '/rh/ponto', icone: 'rh', Pagina: PontoPage }
export const moduloRhFerias: DefinicaoModulo = { id: 'rh_ferias', titulo: 'Férias', rota: '/rh/ferias', icone: 'rh', Pagina: FeriasPage }
