import { useContext } from 'react'
import { OrganizacaoContexto } from './contexto'

export function useOrganizacao(): OrganizacaoContexto {
  const ctx = useContext(OrganizacaoContexto)
  if (!ctx) throw new Error('useOrganizacao precisa estar dentro de OrganizacaoProvider')
  return ctx
}
