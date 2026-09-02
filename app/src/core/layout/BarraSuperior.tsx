import { useState } from 'react'
import { useAuth } from '../auth/useAuth'
import { useOrganizacao } from '../organizacao/useOrganizacao'
import { Icone } from '../ui/Icone'

export function BarraSuperior({ aoAbrirMenu }: { aoAbrirMenu: () => void }) {
  const { usuario, sair } = useAuth()
  const { organizacao } = useOrganizacao()
  const [saindo, setSaindo] = useState(false)

  async function encerrar() {
    setSaindo(true)
    try { await sair() } finally { setSaindo(false) }
  }

  return (
    <header className="flex h-14 items-center justify-between border-b border-line bg-white px-4 md:px-6">
      <div className="flex items-center gap-3">
        <button type="button" onClick={aoAbrirMenu} className="rounded-md p-1.5 hover:bg-surface md:hidden" aria-label="Abrir menu">
          <svg viewBox="0 0 24 24" className="size-6" fill="none" stroke="currentColor" strokeWidth={2}><path d="M4 6h16M4 12h16M4 18h16" /></svg>
        </button>
        <div>
          <p className="text-sm font-medium leading-tight">{organizacao.nome}</p>
          <p className="text-xs text-ink-muted">{usuario?.email}</p>
        </div>
      </div>
      <button
        type="button"
        onClick={encerrar}
        disabled={saindo}
        className="flex items-center gap-2 rounded-md px-3 py-1.5 text-sm text-ink-muted hover:bg-surface hover:text-ink disabled:opacity-60"
      >
        <Icone nome="sair" className="size-4" />
        {saindo ? 'Saindo…' : 'Sair'}
      </button>
    </header>
  )
}
