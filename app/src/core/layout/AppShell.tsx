import { useCallback, useState } from 'react'
import { Outlet } from 'react-router'
import { BarraLateral } from './BarraLateral'
import { BarraSuperior } from './BarraSuperior'
import { OrganizacaoProvider } from '../organizacao/OrganizacaoProvider'
import { ErrorBoundary } from '../erros/ErrorBoundary'
import type { DefinicaoModulo } from '../modulos/tipos'
import { useAuth } from '../auth/useAuth'
import { useInatividade } from '../auth/useInatividade'

export function AppShell({ modulos }: { modulos: DefinicaoModulo[] }) {
  const [menuAberto, setMenuAberto] = useState(false)
  const { sair } = useAuth()
  useInatividade(useCallback(() => { void sair() }, [sair]))

  return (
    <OrganizacaoProvider>
      <div className="flex h-screen overflow-hidden">
        <aside className="hidden w-60 shrink-0 md:block">
          <BarraLateral modulos={modulos} />
        </aside>

        {menuAberto && (
          <div className="fixed inset-0 z-40 flex md:hidden">
            <div className="w-60"><BarraLateral modulos={modulos} aoNavegar={() => setMenuAberto(false)} /></div>
            <button type="button" aria-label="Fechar menu" className="flex-1 bg-black/40" onClick={() => setMenuAberto(false)} />
          </div>
        )}

        <div className="flex min-w-0 flex-1 flex-col">
          <BarraSuperior aoAbrirMenu={() => setMenuAberto(true)} />
          <main className="flex-1 overflow-y-auto p-4 md:p-8">
            <div className="mx-auto max-w-6xl">
              <ErrorBoundary>
                <Outlet />
              </ErrorBoundary>
            </div>
          </main>
        </div>
      </div>
    </OrganizacaoProvider>
  )
}
