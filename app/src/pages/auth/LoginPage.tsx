import { useState, type FormEvent } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../../core/auth/useAuth'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { Alerta } from '../../core/ui/Alerta'
import { Botao } from '../../core/ui/Botao'
import { Campo } from '../../core/ui/Campo'
import { LayoutAuth } from './LayoutAuth'

export function LoginPage() {
  const { entrar } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const destino = (location.state as { de?: string } | null)?.de ?? '/'

  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  async function aoEnviar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    setEnviando(true)
    try {
      await entrar(email.trim(), senha)
      navigate(destino, { replace: true })
    } catch (err) {
      setErro(mensagemDeErro(err))
    } finally {
      setEnviando(false)
    }
  }

  return (
    <LayoutAuth titulo="Entrar" subtitulo="Acesse sua conta para continuar">
      <form onSubmit={aoEnviar} className="space-y-4" noValidate>
        {erro && <Alerta tipo="erro">{erro}</Alerta>}
        <Campo rotulo="E-mail" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        <Campo rotulo="Senha" type="password" autoComplete="current-password" required value={senha} onChange={(e) => setSenha(e.target.value)} />
        <Botao type="submit" className="w-full" carregando={enviando}>Entrar</Botao>
        <p className="text-center text-sm text-ink-muted">
          Ainda não tem conta? <Link to="/cadastro" className="font-medium text-brand-600 hover:underline">Criar conta</Link>
        </p>
      </form>
    </LayoutAuth>
  )
}
