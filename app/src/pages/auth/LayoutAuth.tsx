import type { ReactNode } from 'react'
import { Cartao } from '../../core/ui/Cartao'

export function LayoutAuth({ titulo, subtitulo, children }: { titulo: string; subtitulo: string; children: ReactNode }) {
  return (
    <div className="flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <div className="mb-6 text-center">
          <p className="text-xs font-semibold uppercase tracking-widest text-brand-600">ERP Financeiro Pessoal</p>
          <h1 className="mt-2 text-2xl font-semibold">{titulo}</h1>
          <p className="mt-1 text-sm text-ink-muted">{subtitulo}</p>
        </div>
        <Cartao>{children}</Cartao>
      </div>
    </div>
  )
}
