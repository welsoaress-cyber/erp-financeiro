import { useMemo, useRef, useState } from 'react'
import { NavLink, useLocation } from 'react-router'
import type { DefinicaoModulo } from '../modulos/tipos'
import { Icone } from '../ui/Icone'
import { aplicarOrdem, lerOrdem, salvarOrdem } from './ordemMenu'

const MENTA = '#4ee6b8'

export function BarraLateral({ modulos, aoNavegar }: { modulos: DefinicaoModulo[]; aoNavegar?: () => void }) {
  const { pathname } = useLocation()
  const [ordem, setOrdem] = useState<string[]>(lerOrdem)
  const [arrastando, setArrastando] = useState<string | null>(null)
  const [sobre, setSobre] = useState<string | null>(null)
  const arrastandoRef = useRef<string | null>(null)

  const lista = useMemo(() => aplicarOrdem(modulos, ordem), [modulos, ordem])

  function soltarSobre(idDestino: string) {
    const idOrigem = arrastandoRef.current
    if (!idOrigem || idOrigem === idDestino) return
    const ids = lista.map((m) => m.id)
    const de = ids.indexOf(idOrigem)
    const para = ids.indexOf(idDestino)
    if (de < 0 || para < 0) return
    ids.splice(para, 0, ids.splice(de, 1)[0])
    setOrdem(ids)
    salvarOrdem(ids)
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
        {lista.map((m) => (
          <li
            key={m.id}
            draggable
            onDragStart={(e) => {
              arrastandoRef.current = m.id
              setArrastando(m.id)
              e.dataTransfer.effectAllowed = 'move'
            }}
            onDragEnd={() => {
              arrastandoRef.current = null
              setArrastando(null)
              setSobre(null)
            }}
            onDragOver={(e) => {
              e.preventDefault()
              e.dataTransfer.dropEffect = 'move'
              if (sobre !== m.id) setSobre(m.id)
            }}
            onDrop={(e) => {
              e.preventDefault()
              soltarSobre(m.id)
              setSobre(null)
            }}
            className={arrastando === m.id ? 'opacity-40' : sobre === m.id && arrastando ? 'rounded-full ring-1 ring-white/40' : undefined}
          >
            <NavLink
              to={m.rota}
              end={m.rota === '/'}
              onClick={aoNavegar}
              title="Arraste para reordenar o menu"
              className={({ isActive }) =>
                `flex items-center gap-3 rounded-full px-4 py-2.5 text-sm transition-all ${isActive ? 'font-semibold' : 'text-white/70 hover:bg-white/10 hover:text-white'}`
              }
              style={({ isActive }) => (isActive ? { backgroundColor: MENTA, color: '#08110d', boxShadow: `0 0 18px ${MENTA}66` } : undefined)}
            >
              <Icone nome={m.icone} className="size-5 shrink-0" />
              {m.titulo}
            </NavLink>
            {m.submodulos && pathname.startsWith(m.rota) && (
              <ul className="mt-1 space-y-1 pl-6">
                {m.submodulos.map((s) => (
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
            )}
          </li>
        ))}
      </ul>
      <div className="border-t border-white/10 px-5 py-3 text-xs text-white/50">Financeiro · v0.17</div>
    </nav>
  )
}
