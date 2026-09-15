import { useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router'
import { useAuth } from '../../core/auth/useAuth'
import { validarSenha } from '../../core/auth/validarSenha'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { FundoAuth, MENTA } from './FundoAuth'

/** Destino do link de "Esqueci a senha" do administrador (o e-mail abre esta tela já autenticado). */
export function NovaSenhaPage() {
  const { definirSenha, sessao, carregando } = useAuth()
  const navigate = useNavigate()
  const [senha, setSenha] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  async function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const problemas = validarSenha(senha)
    if (problemas.length) { setErro(problemas.join(' ')); return }
    setErro(null)
    setEnviando(true)
    try { await definirSenha(senha); navigate('/', { replace: true }) } catch (err) { setErro(mensagemDeErro(err)) } finally { setEnviando(false) }
  }

  return (
    <FundoAuth>
      <div className="w-full max-w-md rounded-3xl border border-white/10 bg-white/[0.05] p-8 shadow-[0_30px_80px_rgba(0,0,0,0.55)] backdrop-blur-xl">
        <h1 className="text-3xl font-bold text-white">Nova <span style={{ color: MENTA }}>senha</span></h1>
        {carregando ? (
          <p className="mt-4 text-sm text-white/45">Carregando…</p>
        ) : !sessao ? (
          <>
            <p className="mt-1 text-sm text-white/45">Este link não vale mais. Abra o link do e-mail neste mesmo navegador ou peça outro.</p>
            <Link to="/entrar" className="mt-6 flex h-12 items-center justify-center rounded-full text-base font-semibold" style={{ background: `linear-gradient(90deg, ${MENTA}, #7ef0cd)`, color: '#08110d' }}>Voltar ao login</Link>
          </>
        ) : (
          <>
            <p className="mt-1 text-sm text-white/45">Escolha a senha que você vai usar a partir de agora.</p>
            <form onSubmit={aoEnviar} className="mt-6 space-y-4" noValidate>
              {erro && <p className="rounded-xl border border-red-400/30 bg-red-400/10 px-4 py-3 text-sm text-red-300">{erro}</p>}
              <div>
                <label htmlFor="nova-senha" className="mb-1.5 block text-sm font-medium text-white/80">Nova senha</label>
                <input id="nova-senha" type="password" autoComplete="new-password" required value={senha} onChange={(e) => setSenha(e.target.value)}
                  className="h-12 w-full rounded-xl border border-white/15 bg-black/20 px-4 text-sm text-white outline-none transition placeholder:text-white/25 focus:border-white/40" placeholder="••••••••" />
              </div>
              <button type="submit" disabled={enviando}
                className="mt-2 h-12 w-full rounded-full text-base font-semibold transition hover:brightness-110 disabled:opacity-50"
                style={{ background: `linear-gradient(90deg, ${MENTA}, #7ef0cd)`, color: '#08110d', boxShadow: `0 10px 34px ${MENTA}55` }}>
                {enviando ? 'Salvando…' : 'Salvar senha'}
              </button>
            </form>
          </>
        )}
      </div>
    </FundoAuth>
  )
}
