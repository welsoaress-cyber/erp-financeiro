import { createBrowserRouter, Navigate } from 'react-router'
import { RequireAuth, SomenteAnonimo } from '../core/auth/RequireAuth'
import { AppShell } from '../core/layout/AppShell'
import { LoginPage } from '../pages/auth/LoginPage'
import { CadastroPage } from '../pages/auth/CadastroPage'
import { MODULOS } from './modulos'
import { PortalShell } from '../portal/PortalShell'
import { PortalCadastroPage, PortalLoginEmailPage, PortalLoginPage, PortalNovaSenhaPage, PortalRecuperarPage, PortalVincularPage } from '../portal/pages/PortalAuthPages'
import { PortalFaturaPdfPage, PortalFaturasPage, PortalIndiquePage, PortalPagamentosPage, PortalPlanoPage, PortalPromocoesPage } from '../portal/pages/PortalPages'
import { PortalChamadosPage, PortalDadosPage, PortalFidelidadePage, PortalInicioPage } from '../portal/pages/PortalServnetPages'
import { IndicacaoPublicaPage } from '../portal/pages/IndicacaoPublicaPage'

export const router = createBrowserRouter([
  // Portal do cliente (login próprio, sem acesso ao ERP)
  { path: '/portal/entrar', element: <PortalLoginPage /> },
  { path: '/portal/entrar-email', element: <PortalLoginEmailPage /> },
  { path: '/portal/cadastro', element: <PortalCadastroPage /> },
  { path: '/portal/recuperar', element: <PortalRecuperarPage /> },
  { path: '/portal/nova-senha', element: <PortalNovaSenhaPage /> },
  { path: '/portal/vincular', element: <PortalVincularPage /> },
  { path: '/portal/indicacao/:codigo', element: <IndicacaoPublicaPage /> },
  {
    path: '/portal',
    element: <PortalShell />,
    children: [
      { index: true, element: <PortalInicioPage /> },
      { path: 'faturas', element: <PortalFaturasPage /> },
      { path: 'faturas/:id', element: <PortalFaturaPdfPage /> },
      { path: 'pagamentos', element: <PortalPagamentosPage /> },
      { path: 'plano', element: <PortalPlanoPage /> },
      { path: 'indique', element: <PortalIndiquePage /> },
      { path: 'promocoes', element: <PortalPromocoesPage /> },
      { path: 'fidelidade', element: <PortalFidelidadePage /> },
      { path: 'chamados', element: <PortalChamadosPage /> },
      { path: 'dados', element: <PortalDadosPage /> },
    ],
  },
  {
    element: <SomenteAnonimo />,
    children: [
      { path: '/entrar', element: <LoginPage /> },
      { path: '/cadastro', element: <CadastroPage /> },
    ],
  },
  {
    element: <RequireAuth />,
    children: [
      {
        element: <AppShell modulos={MODULOS} />,
        children: [
          ...MODULOS.map((m) => ({ path: m.rota, element: <m.Pagina /> })),
          ...MODULOS.flatMap((m) => (m.subRotas ?? []).map((s) => ({ path: s.rota, element: <s.Pagina /> }))),
          { path: '*', element: <Navigate to="/" replace /> },
        ],
      },
    ],
  },
])
