import { useState, type FormEvent } from 'react'
import { Link, useLocation, useNavigate } from 'react-router'
import { useAuth } from '../../core/auth/useAuth'
import { useLimiteTentativas } from '../../core/auth/useLimiteTentativas'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { CHAVE_SESSAO_EXPIRADA } from '../../core/auth/useInatividade'

const MENTA = '#4ee6b8'
const emailValido = (v: string) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v.trim())

function Check() {
  return (
    <span className="flex size-5 items-center justify-center rounded-full" style={{ backgroundColor: MENTA }}>
      <svg viewBox="0 0 24 24" className="size-3.5" fill="none" stroke="#08110d" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M20 6 9 17l-5-5" /></svg>
    </span>
  )
}

export function LoginPage() {
  const { entrar } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const destino = (location.state as { de?: string } | null)?.de ?? '/'

  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [verSenha, setVerSenha] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)
  const limite = useLimiteTentativas()
  const [sessaoExpirada, setSessaoExpirada] = useState(() => {
    try { return sessionStorage.getItem(CHAVE_SESSAO_EXPIRADA) === '1' } catch { return false }
  })
  function fecharAvisoExpirada() {
    try { sessionStorage.removeItem(CHAVE_SESSAO_EXPIRADA) } catch { /* ignora */ }
    setSessaoExpirada(false)
  }

  async function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (limite.bloqueado) return
    setErro(null)
    setEnviando(true)
    try {
      await entrar(email.trim(), senha)
      limite.registrarSucesso()
      navigate(destino, { replace: true })
    } catch (err) {
      limite.registrarFalha()
      setErro(mensagemDeErro(err))
    } finally {
      setEnviando(false)
    }
  }

  const campo = 'h-12 w-full rounded-xl border bg-transparent pl-11 pr-11 text-sm text-white outline-none transition placeholder:text-white/30'
  const borda = (ok: boolean) => (ok ? { borderColor: MENTA, boxShadow: `0 0 0 1px ${MENTA}33` } : { borderColor: 'rgba(255,255,255,0.14)' })

  return (
    <div className="flex min-h-screen items-center justify-center px-4 py-10" style={{ background: 'radial-gradient(80% 60% at 50% 0%, #0d1f1a 0%, #070c0a 55%, #050807 100%)' }}>
      <div className="w-full max-w-md rounded-3xl border border-white/10 bg-white/[0.04] p-8 shadow-2xl backdrop-blur">
        <div className="mb-6 flex items-center gap-2">
          <span className="flex size-8 items-center justify-center rounded-full border-2" style={{ borderColor: MENTA }}>
            <span className="size-2.5 rounded-full" style={{ backgroundColor: MENTA }} />
          </span>
          <span className="text-sm font-semibold tracking-[0.3em] text-white/80">ERP FINANCEIRO</span>
        </div>

        <h1 className="text-3xl font-bold text-white">Entrar</h1>
        <p className="mt-1 text-sm text-white/50">Acesse sua conta para continuar.</p>

        <form onSubmit={aoEnviar} className="mt-6 space-y-4" noValidate>
          {erro && <p className="rounded-xl border border-red-400/30 bg-red-400/10 px-4 py-3 text-sm text-red-300">{erro}</p>}
          {limite.mensagem && <p className="rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-white/70">{limite.mensagem}</p>}

          <div>
            <label htmlFor="login-email" className="mb-1.5 block text-sm font-medium text-white/80">E-mail</label>
            <div className="relative">
              <svg viewBox="0 0 24 24" className="absolute left-3.5 top-1/2 size-5 -translate-y-1/2" fill="none" stroke={MENTA} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="5" width="18" height="14" rx="2" /><path d="m3 7 9 6 9-6" /></svg>
              <input id="login-email" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} className={campo} style={borda(emailValido(email))} placeholder="voce@email.com" />
              {emailValido(email) && <span className="absolute right-3.5 top-1/2 -translate-y-1/2"><Check /></span>}
            </div>
          </div>

          <div>
            <label htmlFor="login-senha" className="mb-1.5 block text-sm font-medium text-white/80">Senha</label>
            <div className="relative">
              <svg viewBox="0 0 24 24" className="absolute left-3.5 top-1/2 size-5 -translate-y-1/2" fill="none" stroke={MENTA} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="4" y="10" width="16" height="10" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg>
              <input id="login-senha" type={verSenha ? 'text' : 'password'} autoComplete="current-password" required value={senha} onChange={(e) => setSenha(e.target.value)} className={campo} style={borda(senha.length >= 6)} placeholder="••••••••" />
              <button type="button" aria-label={verSenha ? 'Ocultar senha' : 'Mostrar senha'} onClick={() => setVerSenha((v) => !v)} className="absolute right-3.5 top-1/2 -translate-y-1/2 text-white/40 hover:text-white/80">
                <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">{verSenha ? <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Zm10 3a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z" /> : <path d="m3 3 18 18M10.6 5.1A10.9 10.9 0 0 1 12 5c6.5 0 10 7 10 7a17.6 17.6 0 0 1-3.2 4.2M6.6 6.6C3.9 8.5 2 12 2 12s3.5 7 10 7c1.6 0 3-.4 4.3-1"/>}</svg>
              </button>
            </div>
          </div>

          <button
            type="submit"
            disabled={enviando || limite.bloqueado}
            className="mt-2 h-12 w-full rounded-full text-base font-semibold transition hover:brightness-110 disabled:opacity-50"
            style={{ backgroundColor: MENTA, color: '#08110d', boxShadow: `0 8px 30px ${MENTA}44` }}
          >
            {enviando ? 'Entrando…' : 'Entrar'}
          </button>

          <p className="pt-2 text-center text-sm text-white/50">
            Ainda não tem conta? <Link to="/cadastro" className="font-medium hover:underline" style={{ color: MENTA }}>Criar conta</Link>
          </p>
        </form>
      </div>

      {sessaoExpirada && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 px-4" role="dialog" aria-modal="true">
          <div className="w-full max-w-sm rounded-2xl border border-white/10 bg-[#0d1512] p-6 text-white shadow-2xl">
            <h2 className="text-lg font-semibold">Sessão expirada</h2>
            <p className="mt-2 text-sm text-white/60">Sessão expirada por inatividade. Clique em OK para fazer login novamente.</p>
            <div className="mt-5 flex justify-end">
              <button type="button" onClick={fecharAvisoExpirada} className="h-10 rounded-full px-6 text-sm font-semibold" style={{ backgroundColor: MENTA, color: '#08110d' }}>OK</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
