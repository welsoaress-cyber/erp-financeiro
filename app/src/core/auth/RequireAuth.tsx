import { Navigate, Outlet, useLocation } from 'react-router'
import { useAuth } from './useAuth'
import { Carregando } from '../ui/Carregando'

/** Bloqueia rotas privadas: sem sessão, redireciona para /entrar preservando o destino. */
export function RequireAuth() {
  const { sessao, carregando, usuario } = useAuth()
  const location = useLocation()
  if (carregando) return <Carregando telaCheia texto="Verificando sessão…" />
  if (!sessao) return <Navigate to="/entrar" replace state={{ de: location.pathname }} />
  // login de cliente do portal nunca entra no ERP
  if (usuario?.user_metadata?.portal === 'true') return <Navigate to="/portal" replace />
  return <Outlet />
}

/** Inverso: usuário autenticado não deve ver login/cadastro. */
export function SomenteAnonimo() {
  const { sessao, carregando, usuario } = useAuth()
  if (carregando) return <Carregando telaCheia />
  if (sessao) return <Navigate to={usuario?.user_metadata?.portal === 'true' ? '/portal' : '/'} replace />
  return <Outlet />
}
