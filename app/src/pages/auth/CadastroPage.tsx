import { useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../../core/auth/useAuth'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { Alerta } from '../../core/ui/Alerta'
import { Botao } from '../../core/ui/Botao'
import { Campo } from '../../core/ui/Campo'
import { LayoutAuth } from './LayoutAuth'

export function CadastroPage() {
  const { cadastrar } = useAuth()
  const navigate = useNavigate()

  const [nome, setNome] = useState('')
  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [confirmacao, setConfirmacao] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)
  const [aguardandoEmail, setAguardandoEmail] = useState(false)

  async function aoEnviar(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (nome.trim().length < 2) return setErro('Informe seu nome.')
    if (senha.length < 6) return setErro('A senha deve ter pelo menos 6 caracteres.')
    if (senha !== confirmacao) return setErro('As senhas não conferem.')

    setEnviando(true)
    try {
      const { precisaConfirmarEmail } = await cadastrar(nome.trim(), email.trim(), senha)
      if (precisaConfirmarEmail) setAguardandoEmail(true)
      else navigate('/', { replace: true })
    } catch (err) {
      setErro(mensagemDeErro(err))
    } finally {
      setEnviando(false)
    }
  }

  if (aguardandoEmail) {
    return (
      <LayoutAuth titulo="Confirme seu e-mail" subtitulo="Falta só um passo">
        <Alerta tipo="sucesso" titulo="Cadastro realizado">
          Enviamos um link de confirmação para <strong>{email}</strong>. Depois de confirmar, volte e faça login.
        </Alerta>
        <Link to="/entrar" className="mt-4 block text-center text-sm font-medium text-brand-600 hover:underline">Ir para o login</Link>
      </LayoutAuth>
    )
  }

  return (
    <LayoutAuth titulo="Criar conta" subtitulo="Leva menos de um minuto">
      <form onSubmit={aoEnviar} className="space-y-4" noValidate>
        {erro && <Alerta tipo="erro">{erro}</Alerta>}
        <Campo rotulo="Nome" autoComplete="name" required value={nome} onChange={(e) => setNome(e.target.value)} />
        <Campo rotulo="E-mail" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        <Campo rotulo="Senha" type="password" autoComplete="new-password" required minLength={6} value={senha} onChange={(e) => setSenha(e.target.value)} />
        <Campo rotulo="Confirmar senha" type="password" autoComplete="new-password" required value={confirmacao} onChange={(e) => setConfirmacao(e.target.value)} />
        <Botao type="submit" className="w-full" carregando={enviando}>Criar conta</Botao>
        <p className="text-center text-sm text-ink-muted">
          Já tem conta? <Link to="/entrar" className="font-medium text-brand-600 hover:underline">Entrar</Link>
        </p>
      </form>
    </LayoutAuth>
  )
}
