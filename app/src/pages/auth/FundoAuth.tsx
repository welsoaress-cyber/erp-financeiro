import type { ReactNode } from 'react'

/** Verde-menta da marca do ERP — o mesmo dos botões e do logotipo. */
export const MENTA = '#4ee6b8'
/** Ciano do portal do cliente (padrão visual SERVNET, o mesmo do tema portal-escuro). */
export const CIANO = '#00C4D8'

/**
 * Fundo das telas de acesso: base escura com faixas de luz em diagonal (as "fitas").
 * Tudo é CSS — nenhuma imagem para baixar, então o login abre instantâneo até no 4G.
 * A cor entra por parâmetro: menta no ERP, ciano no portal do cliente.
 */
export function FundoAuth({ children, cor = MENTA, base = '#0e241e', className = '' }: {
  children: ReactNode
  cor?: string
  /** tom do "brilho" no alto do fundo, combinando com a cor */
  base?: string
  className?: string
}) {
  return (
    <div className={`relative flex min-h-screen items-center justify-center overflow-hidden px-4 py-10 ${className}`}
      style={{ background: `radial-gradient(90% 70% at 50% -10%, ${base} 0%, #07100d 55%, #040706 100%)` }}>
      <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
        <span className="absolute -left-1/4 top-[10%] h-24 w-[160%] -rotate-12 rounded-full blur-2xl" style={{ background: `linear-gradient(90deg, transparent, ${cor}80 30%, ${cor}2a 60%, transparent)` }} />
        <span className="absolute -left-1/4 top-[26%] h-10 w-[160%] -rotate-[14deg] rounded-full blur-xl" style={{ background: `linear-gradient(90deg, transparent, ${cor}cc 45%, transparent)` }} />
        <span className="absolute -left-1/4 top-[58%] h-20 w-[160%] -rotate-[20deg] rounded-full blur-2xl" style={{ background: `linear-gradient(90deg, transparent, ${cor}66 40%, transparent)` }} />
        <span className="absolute -left-1/4 bottom-[6%] h-16 w-[160%] -rotate-6 rounded-full blur-2xl" style={{ background: `linear-gradient(90deg, transparent, ${cor}4d 45%, transparent)` }} />
        <span className="absolute left-1/2 top-1/2 size-[46rem] -translate-x-1/2 -translate-y-1/2 rounded-full blur-3xl" style={{ background: `radial-gradient(circle, ${cor}1f, transparent 65%)` }} />
      </div>
      {children}
    </div>
  )
}

/** Cartão de vidro com os cantos em L — a moldura das telas de acesso. */
export function CartaoAuth({ children, cor = MENTA }: { children: ReactNode; cor?: string }) {
  return (
    <div className="relative w-full max-w-md">
      <span className="pointer-events-none absolute -left-2 -top-2 size-16 rounded-tl-3xl border-l-2 border-t-2" style={{ borderColor: `${cor}66` }} />
      <span className="pointer-events-none absolute -bottom-2 -right-2 size-16 rounded-br-3xl border-b-2 border-r-2" style={{ borderColor: `${cor}66` }} />
      <div className="rounded-3xl border border-white/10 bg-white/[0.05] p-8 shadow-[0_30px_80px_rgba(0,0,0,0.55)] backdrop-blur-xl">
        {children}
      </div>
    </div>
  )
}
