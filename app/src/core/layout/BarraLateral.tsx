import { useMemo, useState } from 'react'
import { NavLink, useLocation } from 'react-router'
import type { DefinicaoModulo, MenuGrupo } from '../modulos/tipos'
import { Icone } from '../ui/Icone'
import { useIndicacoesAdmin } from '../../modules/portal/api'

const MENTA = '#4ee6b8'
const CHAVE_GRUPOS = 'erp.menu.grupos_abertos.v1'

function lerAbertos(): Record<string, boolean> {
  try { return JSON.parse(localStorage.getItem(CHAVE_GRUPOS) ?? '{}') as Record<string, boolean> } catch { return {} }
}
function salvarAbertos(estado: Record<string, boolean>) {
  try { localStorage.setItem(CHAVE_GRUPOS, JSON.stringify(estado)) } catch { /* localStorage indisponível */ }
}

export function BarraLateral({ modulos, grupos, raiz, aoNavegar }: {
  modulos: DefinicaoModulo[]
  grupos: MenuGrupo[]
  raiz: string[]
  aoNavegar?: () => void
}) {
  const { pathname } = useLocation()
  const porId = useMemo(() => new Map(modulos.map((m) => [m.id, m])), [modulos])
  const [abertos, setAbertos] = useState<Record<string, boolean>>(lerAbertos)

  // selo de "Novidades": indicados aguardando contato — único badge do menu hoje
  const indicacoes = useIndicacoesAdmin()
  const pendentesNovidades = (indicacoes.data ?? []).filter((i) => i.status === 'pendente').length
  const badges: Partial<Record<string, number>> = { novidades: pendentesNovidades }

  // abre automaticamente o grupo que contém a rota ativa
  const grupoAtivo = useMemo(
    () => grupos.find((g) => g.modulos.some((id) => { const m = porId.get(id); return m && pathname.startsWith(m.rota) && m.rota !== '/' })),
    [grupos, porId, pathname]
  )
  function toggle(id: string) {
    const proximo = { ...abertos, [id]: !abertos[id] }
    setAbertos(proximo); salvarAbertos(proximo)
  }
  // "aberto" também vale para um módulo com submenu (ex.: Financeiro) cuja rota está ativa;
  // só cai no padrão (grupo ativo / rota ativa) enquanto o usuário nunca alternou esse item
  const estaAberto = (id: string, rotaAtiva = false) => (id in abertos ? abertos[id] : (grupoAtivo?.id === id || rotaAtiva))

  const modulosRaiz = raiz.map((id) => porId.get(id)).filter(Boolean) as DefinicaoModulo[]

  function renderModulo(m: DefinicaoModulo, indentado = false) {
    const contagem = badges[m.id]
    return (
      <li key={m.id}>
        <NavLink
          to={m.rota}
          end={m.rota === '/'}
          onClick={aoNavegar}
          className={({ isActive }) =>
            `flex items-center gap-3 rounded-full ${indentado ? 'ml-4 pl-6 pr-4' : 'px-4'} py-2.5 text-sm transition-all ${isActive ? 'font-semibold' : 'text-white/70 hover:bg-white/10 hover:text-white'}`
          }
          style={({ isActive }) => (isActive ? { backgroundColor: MENTA, color: '#08110d', boxShadow: `0 0 18px ${MENTA}66` } : undefined)}
        >
          <Icone nome={m.icone} className="size-5 shrink-0" />
          <span className="flex-1">{m.titulo}</span>
          {Boolean(contagem) && (
            <span className="flex h-5 min-w-5 shrink-0 items-center justify-center rounded-full bg-red-500 px-1.5 text-xs font-semibold text-white">
              {contagem}
            </span>
          )}
        </NavLink>
      </li>
    )
  }

  /** Cabeçalho de grupo colapsável (mesmo visual para Cadastros/Operação/… e para um módulo raiz com submenu, ex.: Financeiro). */
  function renderCabecalhoGrupo(titulo: string, icone: DefinicaoModulo['icone'], aberto: boolean, onToggle: () => void) {
    return (
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center gap-3 rounded-full px-4 py-2.5 text-sm text-white/70 transition-all hover:bg-white/10 hover:text-white"
        aria-expanded={aberto}
      >
        <Icone nome={icone} className="size-5 shrink-0" />
        <span className="flex-1 text-left">{titulo}</span>
        <span className={`text-xs transition-transform ${aberto ? 'rotate-90' : ''}`}>▸</span>
      </button>
    )
  }

  function renderSubitens(itens: { id: string; titulo: string; rota: string }[]) {
    return (
      <ul className="mt-1 space-y-1 pl-6">
        {itens.map((s) => (
          <li key={s.id}>
            <NavLink
              to={s.rota}
              onClick={aoNavegar}
              className={({ isActive }) =>
                `block rounded-full border px-4 py-1.5 text-sm transition-all ${isActive ? 'font-medium' : 'border-transparent text-white/60 hover:text-white'}`
              }
              style={({ isActive }) => (isActive ? { backgroundColor: `${MENTA}22`, color: MENTA, borderColor: `${MENTA}55` } : undefined)}
            >
              {s.titulo}
            </NavLink>
          </li>
        ))}
      </ul>
    )
  }

  /** Módulo raiz com submódulos (hoje só Financeiro): mesmo cabeçalho colapsável dos grupos. */
  function renderModuloComSubmenu(m: DefinicaoModulo) {
    const rotaAtiva = pathname.startsWith(m.rota)
    const aberto = estaAberto(m.id, rotaAtiva)
    return (
      <li key={m.id}>
        {renderCabecalhoGrupo(m.titulo, m.icone, aberto, () => toggle(m.id))}
        {aberto && renderSubitens(m.submodulos!)}
      </li>
    )
  }

  return (
    <nav className="flex h-full flex-col text-white" style={{ background: 'linear-gradient(180deg, #0d1f1a 0%, #070c0a 60%, #050807 100%)' }}>
      <div className="flex h-14 items-center gap-2 border-b border-white/10 px-5">
        <span className="flex size-6 items-center justify-center rounded-full border-2" style={{ borderColor: MENTA }}>
          <span className="size-2 rounded-full" style={{ backgroundColor: MENTA }} />
        </span>
        <span className="text-sm font-semibold tracking-wide">ERP Financeiro</span>
      </div>
      <ul className="flex-1 space-y-1.5 overflow-y-auto p-3">
        {modulosRaiz.filter((m) => m.id === 'dashboard').map((m) => renderModulo(m))}
        {modulosRaiz.filter((m) => m.id === 'novidades').map((m) => renderModulo(m))}
        {modulosRaiz.filter((m) => m.id === 'financeiro' && m.submodulos).map((m) => renderModuloComSubmenu(m))}
        {grupos.map((g) => {
          const filhos = g.modulos.map((id) => porId.get(id)).filter(Boolean) as DefinicaoModulo[]
          if (filhos.length === 0) return null
          const aberto = estaAberto(g.id)
          return (
            <li key={g.id}>
              {renderCabecalhoGrupo(g.titulo, g.icone, aberto, () => toggle(g.id))}
              {aberto && (
                <ul className="mt-1 space-y-1">
                  {filhos.map((m) => renderModulo(m, true))}
                </ul>
              )}
            </li>
          )
        })}
        {modulosRaiz.filter((m) => m.id !== 'dashboard' && m.id !== 'novidades' && m.id !== 'financeiro').map((m) => renderModulo(m))}
      </ul>
      <div className="border-t border-white/10 px-5 py-3 text-xs text-white/50">Financeiro · v0.19</div>
    </nav>
  )
}
