import { createContext } from 'react'
import type { Session, User } from '@supabase/supabase-js'

export interface AuthContexto {
  sessao: Session | null
  usuario: User | null
  carregando: boolean
  entrar: (email: string, senha: string) => Promise<void>
  cadastrar: (nome: string, email: string, senha: string) => Promise<{ precisaConfirmarEmail: boolean }>
  sair: () => Promise<void>
}

export const AuthContexto = createContext<AuthContexto | null>(null)
