import { NavLink, Navigate, Outlet } from 'react-router'
import { useAuth } from '../core/auth/useAuth'
import { Carregando } from '../core/ui/Carregando'
import { Botao } from '../core/ui/Botao'
import { useMeuTecnico } from './api'

/** Shell mobile do técnico: só chamados e bolsa. Sem tempos, sem ERP. */
export function TecnicoShell() {
  const { sessao, carregando, usuario, sair } = useAuth()
  const eu = useMeuTecnico()
  if (carregando) return <Carregando telaCheia texto="Verificando sessão…" />
  if (!sessao) return <Navigate to="/tecnico/entrar" replace />
  if (usuario?.user_metadata?.tecnico !== 'true') return <Navigate to="/" replace />
  if (eu.isPending) return <Carregando telaCheia texto="Carregando…" />
  if (!eu.data) {
    return (
      <div className="mx-auto mt-16 max-w-sm space-y-4 p-6 text-center">
        <p className="text-sm">Seu login ainda não está vinculado a um técnico ativo. Fale com o administrador.</p>
        <Botao variante="secundario" onClick={() => void sair()}>Sair</Botao>
      </div>
    )
  }
  const aba = 'flex-1 py-3 text-center text-sm font-medium'
  return (
    <div className="mx-auto flex min-h-screen max-w-lg flex-col bg-surface">
      <header className="flex items-center justify-between border-b border-line bg-white px-4 py-3">
        <div>
          <p className="text-sm font-semibold">{eu.data.nome}</p>
          <p className="text-xs text-ink-muted">Área do técnico</p>
        </div>
        <button type="button" className="text-xs font-medium text-brand-700 hover:underline" onClick={() => void sair()}>Sair</button>
      </header>
      <main className="flex-1 p-4 pb-20">
        <Outlet context={eu.data} />
      </main>
      <nav className="fixed inset-x-0 bottom-0 mx-auto flex max-w-lg border-t border-line bg-white">
        <NavLink to="/tecnico" end className={({ isActive }) => `${aba} ${isActive ? 'text-brand-700' : 'text-ink-muted'}`}>Meus chamados</NavLink>
        <NavLink to="/tecnico/bolsa" className={({ isActive }) => `${aba} ${isActive ? 'text-brand-700' : 'text-ink-muted'}`}>Minha bolsa</NavLink>
      </nav>
    </div>
  )
}
