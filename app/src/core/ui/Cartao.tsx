import type { ReactNode } from 'react'

/** Padding informado pelo chamador (p-0, p-4, px-3, py-6…) vence o padrão p-6.
 *  Sem isso o Tailwind resolve pela ordem do CSS gerado e o p-6 da base ganhava
 *  sempre — `Cartao className="p-0"` (tabelas e listas) vinha com 24px de sobra,
 *  o que no celular come quase 15% da largura útil. */
export function Cartao({ children, className = '' }: { children: ReactNode; className?: string }) {
  const temPadding = /(^|\s)(p|px|py|ps|pe|pt|pr|pb|pl)-/.test(className)
  return <div className={`rounded-lg border border-line bg-white ${temPadding ? '' : 'p-6'} shadow-sm ${className}`}>{children}</div>
}
