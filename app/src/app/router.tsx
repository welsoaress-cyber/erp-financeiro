import { createBrowserRouter, Navigate } from 'react-router'
import { RequireAuth, SomenteAnonimo } from '../core/auth/RequireAuth'
import { AppShell } from '../core/layout/AppShell'
import { LoginPage } from '../pages/auth/LoginPage'
import { CadastroPage } from '../pages/auth/CadastroPage'
import { MODULOS } from './modulos'

export const router = createBrowserRouter([
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
