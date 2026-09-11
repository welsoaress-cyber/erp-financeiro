import { useState, type FormEvent } from 'react'
import { Navigate, useNavigate } from 'react-router'
import { useAuth } from '../../core/auth/useAuth'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'

/** Login do técnico: usuário e senha (sem e-mail). Internamente vira login@tecnico.local. */
export function TecnicoLoginPage() {
  const { entrar, sessao, usuario } = useAuth()
  const navigate = useNavigate()
  const [login, setLogin] = useState('')
  const [senha, setSenha] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  if (sessao && usuario?.user_metadata?.tecnico === 'true') return <Navigate to="/tecnico" replace />

  async function aoEnviar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    setEnviando(true)
    try {
      const email = login.includes('@') ? login.trim() : `${login.trim().toLowerCase()}@tecnico.local`
      await entrar(email, senha)
      navigate('/tecnico', { replace: true })
    } catch (err) {
      setErro(mensagemDeErro(err))
    } finally {
      setEnviando(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface px-4">
      <form onSubmit={(e) => void aoEnviar(e)} className="w-full max-w-sm space-y-4 rounded-xl border border-line bg-white p-6">
        <div>
          <h1 className="text-lg font-semibold">Área do técnico</h1>
          <p className="text-sm text-ink-muted">Entre com o usuário e a senha que o administrador criou.</p>
        </div>
        {erro && <p className="rounded-md bg-red-50 p-3 text-sm text-red-800">{erro}</p>}
        <label className="block text-sm font-medium">Usuário
          <input value={login} onChange={(e) => setLogin(e.target.value)} autoCapitalize="none" autoComplete="username" className="mt-1 h-12 w-full rounded-md border border-line px-3 text-sm" placeholder="ex.: joao" />
        </label>
        <label className="block text-sm font-medium">Senha
          <input type="password" value={senha} onChange={(e) => setSenha(e.target.value)} autoComplete="current-password" className="mt-1 h-12 w-full rounded-md border border-line px-3 text-sm" />
        </label>
        <button type="submit" disabled={enviando || !login.trim() || !senha} className="h-12 w-full rounded-md bg-brand-600 text-sm font-medium text-white hover:bg-brand-700 disabled:opacity-60">
          {enviando ? 'Entrando…' : 'Entrar'}
        </button>
      </form>
    </div>
  )
}
