import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { PortalAdminPage } from './pages/PortalAdminPage'
export const moduloPortal: DefinicaoModulo = { id: 'portal', titulo: 'Portal do cliente', rota: '/portal-admin', icone: 'portal', Pagina: PortalAdminPage }
