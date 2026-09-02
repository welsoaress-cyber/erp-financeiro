import { useContext } from 'react'
import { AuthContexto } from './contexto'

export function useAuth(): AuthContexto {
  const ctx = useContext(AuthContexto)
  if (!ctx) throw new Error('useAuth precisa estar dentro de AuthProvider')
  return ctx
}
