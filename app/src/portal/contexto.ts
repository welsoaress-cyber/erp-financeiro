import { createContext, useContext } from 'react'
import type { PortalResumo } from './tipos'
export const PortalContexto = createContext<PortalResumo | null>(null)
export function usePortal(): PortalResumo {
  const v = useContext(PortalContexto)
  if (!v) throw new Error('usePortal fora do PortalShell')
  return v
}
