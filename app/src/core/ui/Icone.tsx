import type { SVGProps } from 'react'

export type NomeIcone = 'painel' | 'lancamentos' | 'contas' | 'categorias' | 'negocios' | 'pessoas' | 'configuracoes' | 'sair'

const CAMINHOS: Record<NomeIcone, string> = {
  painel: 'M3 13h8V3H3v10Zm0 8h8v-6H3v6Zm10 0h8V11h-8v10Zm0-18v6h8V3h-8Z',
  lancamentos: 'M4 6h16M4 12h10M4 18h7M17 15l3 3-3 3',
  contas: 'M3 7h18v12H3V7Zm0 4h18M7 15h3',
  categorias: 'M4 4h6v6H4V4Zm10 0h6v6h-6V4ZM4 14h6v6H4v-6Zm10 0h6v6h-6v-6Z',
  negocios: 'M3 8h18v11H3V8Zm6 0V5h6v3M3 13h18',
  pessoas: 'M16 19v-1a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v1M9.5 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Zm7-1a3 3 0 1 0 0-6M21 19v-1a4 4 0 0 0-3-3.87',
  configuracoes: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm7.4-3a7.4 7.4 0 0 0-.1-1l2-1.5-2-3.5-2.4 1a7.6 7.6 0 0 0-1.7-1L14.8 3H9.2l-.4 2.6a7.6 7.6 0 0 0-1.7 1l-2.4-1-2 3.5 2 1.5a7.4 7.4 0 0 0 0 2l-2 1.5 2 3.5 2.4-1a7.6 7.6 0 0 0 1.7 1l.4 2.6h5.6l.4-2.6a7.6 7.6 0 0 0 1.7-1l2.4 1 2-3.5-2-1.5c.1-.3.1-.7.1-1Z',
  sair: 'M10 17l5-5-5-5M15 12H3M13 3h6v18h-6',
}

export function Icone({ nome, ...rest }: { nome: NomeIcone } & SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...rest}>
      <path d={CAMINHOS[nome]} />
    </svg>
  )
}
