import type { SVGProps } from 'react'

export type NomeIcone = 'painel' | 'financeiro' | 'lancamentos' | 'contas' | 'cartao' | 'categorias' | 'negocios' | 'pessoas' | 'contratos' | 'apps' | 'notificacoes' | 'disparos' | 'ftth' | 'estoque' | 'os' | 'gerencial' | 'portal' | 'indicacoes' | 'configuracoes' | 'sair'

const CAMINHOS: Record<NomeIcone, string> = {
  painel: 'M3 13h8V3H3v10Zm0 8h8v-6H3v6Zm10 0h8V11h-8v10Zm0-18v6h8V3h-8Z',
  cartao: 'M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2Zm0 4H4V6h16v2Zm0 10H4v-6h16v6ZM6 15h4v2H6v-2Z',
  financeiro: 'M3 5h18v14H3V5Zm0 4h18M7 14h4M12 2v3M12 19v3',
  lancamentos: 'M4 6h16M4 12h10M4 18h7M17 15l3 3-3 3',
  contas: 'M3 7h18v12H3V7Zm0 4h18M7 15h3',
  categorias: 'M4 4h6v6H4V4Zm10 0h6v6h-6V4ZM4 14h6v6H4v-6Zm10 0h6v6h-6v-6Z',
  negocios: 'M3 8h18v11H3V8Zm6 0V5h6v3M3 13h18',
  pessoas: 'M16 19v-1a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v1M9.5 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Zm7-1a3 3 0 1 0 0-6M21 19v-1a4 4 0 0 0-3-3.87',
  contratos: 'M6 3h9l4 4v14H6V3Zm9 0v4h4M9 12h6M9 16h6',
  apps: 'M5 3h5v5H5V3Zm9 0h5v5h-5V3ZM5 12h5v5H5v-5Zm9 0h5v5h-5v-5ZM3 21h18',
  notificacoes: 'M6 16V11a6 6 0 1 1 12 0v5l2 2H4l2-2Zm4 3a2 2 0 0 0 4 0',
  disparos: 'M3 11l17-6v14L3 13v-2Zm5 3v4a2 2 0 0 0 4 0v-2.5M20 8v6',
  ftth: 'M12 21s-6-5.3-6-10a6 6 0 1 1 12 0c0 4.7-6 10-6 10Zm0-8a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z',
  estoque: 'M21 8.2 12 3 3 8.2v7.6L12 21l9-5.2V8.2ZM12 5.3l6.5 3.7L12 12.8 5.5 9 12 5.3ZM5 10.8l6 3.5v4.9l-6-3.5v-4.9Zm8 8.4v-4.9l6-3.5v4.9l-6 3.5Z',
  gerencial: 'M4 20V10M10 20V4M16 20v-7M22 20H2M19 6l3-3-3-3',
  os: 'M14 3l7 7-9 9-4 1-3 3-2-2 3-3 1-4 9-9Zm-2.5 5.5L16 13M5 16l3 3',
  portal: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm-7 9a7 7 0 0 1 14 0M3 3h18v18H3z',
  indicacoes: 'M20 12v9H4v-9M2 7h20v5H2V7Zm10 0v14M12 7s-2-4.5-5-4.5A2.25 2.25 0 0 0 7 7h5Zm0 0s2-4.5 5-4.5A2.25 2.25 0 0 1 17 7h-5Z',
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
