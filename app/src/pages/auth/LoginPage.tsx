import { useState, type FormEvent } from 'react'
import { Link, useLocation, useNavigate } from 'react-router'
import { useAuth } from '../../core/auth/useAuth'
import { useLimiteTentativas } from '../../core/auth/useLimiteTentativas'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { Alerta } from '../../core/ui/Alerta'
import { Botao } from '../../core/ui/Botao'
import { Campo } from '../../core/ui/Campo'
import { LayoutAuth } from './LayoutAuth'
import { Modal } from '../../core/ui/Modal'
import { CHAVE_SESSAO_EXPIRADA } from '../../core/auth/useInatividade'

export function LoginPage() {
  const { entrar } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const destino = (location.state as { de?: string } | null)?.de ?? '/'

  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
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

  return (
    <LayoutAuth titulo="Entrar" subtitulo="Acesse sua conta para continuar">
      <form onSubmit={aoEnviar} className="space-y-4" noValidate>
        {erro && <Alerta tipo="erro">{erro}</Alerta>}
        {limite.mensagem && <Alerta tipo="info">{limite.mensagem}</Alerta>}
        <Campo rotulo="E-mail" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        <Campo rotulo="Senha" type="password" autoComplete="current-password" required value={senha} onChange={(e) => setSenha(e.target.value)} />
        <Botao type="submit" className="w-full" carregando={enviando} disabled={limite.bloqueado}>Entrar</Botao>
        <p className="text-center text-sm text-ink-muted">
          Ainda não tem conta? <Link to="/cadastro" className="font-medium text-brand-600 hover:underline">Criar conta</Link>
        </p>
      </form>
      <Modal aberto={sessaoExpirada} aoFechar={fecharAvisoExpirada} titulo="Sessão expirada">
        <p className="text-sm text-ink-muted">Sessão expirada por inatividade. Clique em OK para fazer login novamente.</p>
        <div className="mt-4 flex justify-end"><Botao onClick={fecharAvisoExpirada}>OK</Botao></div>
      </Modal>
    </LayoutAuth>
  )
}
