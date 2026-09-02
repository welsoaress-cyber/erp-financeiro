import { createContext } from 'react'

export interface Organizacao {
  id: string
  nome: string
  papel: 'proprietario' | 'membro'
}

export interface OrganizacaoContexto {
  organizacao: Organizacao
  organizacoes: Organizacao[]
}

export const OrganizacaoContexto = createContext<OrganizacaoContexto | null>(null)
