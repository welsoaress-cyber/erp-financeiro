import { NavLink } from 'react-router'
import type { DefinicaoModulo } from '../modulos/tipos'
import { Icone } from '../ui/Icone'

export function BarraLateral({ modulos, aoNavegar }: { modulos: DefinicaoModulo[]; aoNavegar?: () => void }) {
  return (
    <nav className="flex h-full flex-col bg-brand-900 text-white">
      <div className="flex h-14 items-center border-b border-white/10 px-5">
        <span className="text-sm font-semibold tracking-wide">ERP Financeiro</span>
      </div>
      <ul className="flex-1 space-y-0.5 p-3">
        {modulos.map((m) => (
          <li key={m.id}>
            <NavLink
              to={m.rota}
              end={m.rota === '/'}
              onClick={aoNavegar}
              className={({ isActive }) =>
                `flex items-center gap-3 rounded-md px-3 py-2 text-sm transition-colors ${isActive ? 'bg-white/15 font-medium' : 'text-white/75 hover:bg-white/10 hover:text-white'}`
              }
            >
              <Icone nome={m.icone} className="size-5 shrink-0" />
              {m.titulo}
            </NavLink>
          </li>
        ))}
      </ul>
      <div className="border-t border-white/10 px-5 py-3 text-xs text-white/50">Notificações · v0.14</div>
    </nav>
  )
}
