import { useState, type FormEvent } from 'react'
import { Navigate, useNavigate } from 'react-router'
import { useAuth } from '../../core/auth/useAuth'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { CartaoAuth, FundoAuth, MENTA } from '../../pages/auth/FundoAuth'

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

  // campos grandes de propósito: o técnico entra no celular, muitas vezes com uma mão só
  const campo = 'mt-1 h-12 w-full rounded-xl border border-white/15 bg-black/20 px-3 text-sm text-white outline-none transition placeholder:text-white/25 focus:border-white/40'
  return (
    <FundoAuth>
      <CartaoAuth>
        <form onSubmit={(e) => void aoEnviar(e)} className="space-y-4">
          <div className="mb-2 flex items-center gap-2">
            <span className="flex size-8 items-center justify-center rounded-full border-2" style={{ borderColor: MENTA }}>
              <span className="size-2.5 rounded-full" style={{ backgroundColor: MENTA }} />
            </span>
            <span className="text-xs font-semibold tracking-[0.3em] text-white/70">ÁREA DO TÉCNICO</span>
          </div>
          <div>
            <h1 className="text-3xl font-bold text-white">Bem-vindo, <span style={{ color: MENTA }}>técnico</span></h1>
            <p className="mt-1 text-sm text-white/45">Entre com o usuário e a senha que o administrador criou.</p>
          </div>
          {erro && <p className="rounded-xl border border-red-400/30 bg-red-400/10 px-4 py-3 text-sm text-red-300">{erro}</p>}
          <label className="block text-sm font-medium text-white/80">Usuário
            <input value={login} onChange={(e) => setLogin(e.target.value)} autoCapitalize="none" autoComplete="username" className={campo} placeholder="ex.: joao" />
          </label>
          <label className="block text-sm font-medium text-white/80">Senha
            <input type="password" value={senha} onChange={(e) => setSenha(e.target.value)} autoComplete="current-password" className={campo} />
          </label>
          <button type="submit" disabled={enviando || !login.trim() || !senha}
            className="mt-2 h-12 w-full rounded-full text-base font-semibold transition hover:brightness-110 disabled:opacity-50"
            style={{ background: `linear-gradient(90deg, ${MENTA}, #7ef0cd)`, color: '#08110d', boxShadow: `0 10px 34px ${MENTA}55` }}>
            {enviando ? 'Entrando…' : 'Entrar'}
          </button>
        </form>
      </CartaoAuth>
    </FundoAuth>
  )
}
