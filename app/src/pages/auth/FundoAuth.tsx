import type { ReactNode } from 'react'

/** Verde-menta da marca — o mesmo dos botões e do logotipo. */
export const MENTA = '#4ee6b8'

/**
 * Fundo das telas de acesso: base escura com faixas de luz em diagonal (as "fitas").
 * Tudo é CSS — nenhuma imagem para baixar, então o login abre instantâneo até no 4G.
 */
export function FundoAuth({ children }: { children: ReactNode }) {
  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden px-4 py-10" style={{ background: 'radial-gradient(90% 70% at 50% -10%, #0e241e 0%, #07100d 55%, #040706 100%)' }}>
      <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
        <span className="absolute -left-1/4 top-[10%] h-24 w-[160%] -rotate-12 rounded-full blur-2xl" style={{ background: `linear-gradient(90deg, transparent, ${MENTA}80 30%, ${MENTA}2a 60%, transparent)` }} />
        <span className="absolute -left-1/4 top-[26%] h-10 w-[160%] -rotate-[14deg] rounded-full blur-xl" style={{ background: `linear-gradient(90deg, transparent, #b6ffe6cc 45%, transparent)` }} />
        <span className="absolute -left-1/4 top-[58%] h-20 w-[160%] -rotate-[20deg] rounded-full blur-2xl" style={{ background: `linear-gradient(90deg, transparent, #7ef0cd66 40%, transparent)` }} />
        <span className="absolute -left-1/4 bottom-[6%] h-16 w-[160%] -rotate-6 rounded-full blur-2xl" style={{ background: `linear-gradient(90deg, transparent, ${MENTA}4d 45%, transparent)` }} />
        <span className="absolute left-1/2 top-1/2 size-[46rem] -translate-x-1/2 -translate-y-1/2 rounded-full blur-3xl" style={{ background: `radial-gradient(circle, ${MENTA}1f, transparent 65%)` }} />
      </div>
      {children}
    </div>
  )
}
