import { useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../../core/auth/useAuth'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { Alerta } from '../../core/ui/Alerta'
import { Botao } from '../../core/ui/Botao'
import { Campo } from '../../core/ui/Campo'
import { LayoutAuth } from './LayoutAuth'
import { REGRAS_SENHA, temCaractereEspecial, validarSenha } from '../../core/auth/validarSenha'

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
    const errosSenha = validarSenha(senha)
    if (errosSenha.length > 0) return setErro(errosSenha[0])
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
        <div className="space-y-2">
          <Campo rotulo="Senha" type="password" autoComplete="new-password" required minLength={8} value={senha} onChange={(e) => setSenha(e.target.value)} />
          <ul className="grid grid-cols-2 gap-x-3 gap-y-1 text-xs" aria-label="Requisitos da senha">
            {REGRAS_SENHA.map((r) => (
              <li key={r.id} className={r.ok(senha) ? 'text-green-700' : 'text-ink-muted'}>{r.ok(senha) ? '✓' : '○'} {r.texto}</li>
            ))}
            <li className={temCaractereEspecial(senha) ? 'text-green-700' : 'text-ink-muted'}>{temCaractereEspecial(senha) ? '✓' : '○'} 1 caractere especial (recomendado)</li>
          </ul>
        </div>
        <Campo rotulo="Confirmar senha" type="password" autoComplete="new-password" required value={confirmacao} onChange={(e) => setConfirmacao(e.target.value)} />
        <Botao type="submit" className="w-full" carregando={enviando}>Criar conta</Botao>
        <p className="text-center text-sm text-ink-muted">
          Já tem conta? <Link to="/entrar" className="font-medium text-brand-600 hover:underline">Entrar</Link>
        </p>
      </form>
    </LayoutAuth>
  )
}
