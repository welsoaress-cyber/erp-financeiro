import { useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { AuthContexto } from './contexto'
import { supabase } from '../supabase/client'

export function AuthProvider({ children }: { children: ReactNode }) {
  const [sessao, setSessao] = useState<Session | null>(null)
  const [carregando, setCarregando] = useState(true)

  useEffect(() => {
    let ativo = true
    supabase.auth.getSession().then(({ data }) => {
      if (!ativo) return
      setSessao(data.session)
      setCarregando(false)
    })
    const { data: assinatura } = supabase.auth.onAuthStateChange((_evento, novaSessao) => {
      setSessao(novaSessao)
      setCarregando(false)
    })
    return () => {
      ativo = false
      assinatura.subscription.unsubscribe()
    }
  }, [])

  const valor = useMemo<AuthContexto>(() => ({
    sessao,
    usuario: sessao?.user ?? null,
    carregando,
    async entrar(email, senha) {
      const { error } = await supabase.auth.signInWithPassword({ email, password: senha })
      if (error) throw error
    },
    async cadastrar(nome, email, senha) {
      const { data, error } = await supabase.auth.signUp({
        email,
        password: senha,
        options: { data: { nome } },
      })
      if (error) throw error
      return { precisaConfirmarEmail: !data.session }
    },
    async cadastrarPortal(email, senha) {
      const { data, error } = await supabase.auth.signUp({ email, password: senha, options: { data: { portal: 'true' } } })
      if (error) throw error
      return { precisaConfirmarEmail: !data.session }
    },
    async recuperarSenha(email, redirecionarPara) {
      const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: redirecionarPara })
      if (error) throw error
    },
    async definirSenha(senha) {
      const { error } = await supabase.auth.updateUser({ password: senha })
      if (error) throw error
    },
    async sair() {
      const { error } = await supabase.auth.signOut()
      if (error) throw error
    },
  }), [sessao, carregando])

  return <AuthContexto.Provider value={valor}>{children}</AuthContexto.Provider>
}
