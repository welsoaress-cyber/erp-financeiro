import type { ReactNode } from 'react'

export function Cartao({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`rounded-lg border border-line bg-white p-6 shadow-sm ${className}`}>{children}</div>
}
