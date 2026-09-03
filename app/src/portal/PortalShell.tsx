import { useCallback } from 'react'
import { NavLink, Navigate, Outlet, useLocation } from 'react-router'
import { useAuth } from '../core/auth/useAuth'
import { useInatividade } from '../core/auth/useInatividade'
import { Carregando } from '../core/ui/Carregando'
import { Alerta } from '../core/ui/Alerta'
import { Botao } from '../core/ui/Botao'
import { ErrorBoundary } from '../core/erros/ErrorBoundary'
import { mensagemDeErro } from '../core/erros/mensagemDeErro'
import { usePortalResumo } from './api'
import { PortalContexto } from './contexto'

const MENU = [
  { rota: '/portal', rotulo: 'Início', fim: true },
  { rota: '/portal/faturas', rotulo: 'Faturas' },
  { rota: '/portal/pagamentos', rotulo: 'Pagamentos' },
  { rota: '/portal/plano', rotulo: 'Meu plano' },
  { rota: '/portal/fidelidade', rotulo: 'Fidelidade' },
  { rota: '/portal/indique', rotulo: 'Indique e ganhe' },
  { rota: '/portal/promocoes', rotulo: 'Promoções' },
  { rota: '/portal/chamados', rotulo: 'Chamados' },
  { rota: '/portal/dados', rotulo: 'Meus dados' },
]

/** Área do cliente: exige sessão e vínculo com uma pessoa. Sem vínculo → /portal/vincular. Tema escuro (padrão) ou claro pela configuração do negócio. */
export function PortalShell() {
  const { sessao, carregando, sair, usuario } = useAuth()
  const location = useLocation()
  const resumo = usePortalResumo()
  useInatividade(useCallback(() => { void sair() }, [sair]))

  if (carregando) return <Carregando telaCheia texto="Verificando acesso…" />
  if (!sessao) return <Navigate to="/portal/entrar" replace state={{ de: location.pathname }} />
  if (usuario?.user_metadata?.portal !== 'true') return <Navigate to="/" replace />
  if (resumo.isPending || (resumo.data === null && resumo.isFetching)) return <Carregando telaCheia texto="Carregando seus dados…" />
  if (resumo.isError) return <div className="mx-auto mt-16 max-w-lg p-6"><Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(resumo.error)}</Alerta><div className="mt-3"><Botao variante="secundario" onClick={() => sair()}>Sair</Botao></div></div>
  if (!resumo.data) return <Navigate to="/portal/vincular" replace />

  const cfg = resumo.data.negocios.find((n) => n.portal)?.portal ?? null
  const escuro = (cfg?.tema ?? 'escuro') === 'escuro'
  const cor = escuro ? '#061520' : (cfg?.cor_primaria ?? '#1e3a8a')
  const nomeNegocio = resumo.data.negocios.map((n) => n.nome).join(' · ') || 'Portal do cliente'
  return (
    <PortalContexto.Provider value={resumo.data}>
      <div className={`min-h-screen bg-surface text-ink ${escuro ? 'portal-escuro' : ''}`}>
        <header className={escuro ? 'border-b border-line' : 'text-white'} style={{ backgroundColor: cor }}>
          <div className="mx-auto flex max-w-4xl items-center justify-between px-4 py-3">
            <div className="flex items-center gap-3">
              {cfg?.logo_url && <img src={cfg.logo_url} alt="" className="h-8 w-auto rounded bg-white/90 p-0.5" />}
              <div><p className={`text-sm font-semibold leading-tight ${escuro ? 'text-brand-600' : ''}`}>{nomeNegocio}</p><p className="text-xs opacity-80">{resumo.data.pessoa.nome}</p></div>
            </div>
            <button type="button" onClick={() => sair()} className={`rounded-md px-3 py-1.5 text-sm ${escuro ? 'text-ink-muted hover:text-ink' : 'hover:bg-white/10'}`}>Sair</button>
          </div>
          <nav className="mx-auto max-w-4xl overflow-x-auto px-2">
            <ul className="flex gap-1 text-sm">
              {MENU.map((m) => (
                <li key={m.rota}><NavLink to={m.rota} end={m.fim} className={({ isActive }) => `block whitespace-nowrap rounded-t-md px-3 py-2 ${isActive ? 'bg-surface text-ink font-medium' : escuro ? 'text-ink-muted hover:text-ink' : 'text-white/85 hover:bg-white/10'}`}>{m.rotulo}</NavLink></li>
              ))}
            </ul>
          </nav>
        </header>
        <main className="mx-auto max-w-4xl p-4 md:p-6"><ErrorBoundary><Outlet /></ErrorBoundary></main>
        <footer className="mx-auto max-w-4xl px-4 pb-6 text-center text-xs text-ink-muted">Portal do cliente · {nomeNegocio}</footer>
      </div>
    </PortalContexto.Provider>
  )
}
