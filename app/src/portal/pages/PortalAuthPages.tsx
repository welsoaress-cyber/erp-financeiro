import { useState, type FormEvent } from 'react'
import { Link, Navigate, useNavigate } from 'react-router'
import { useAuth } from '../../core/auth/useAuth'
import { useLimiteTentativas } from '../../core/auth/useLimiteTentativas'
import { validarSenha } from '../../core/auth/validarSenha'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { Alerta } from '../../core/ui/Alerta'
import { Botao } from '../../core/ui/Botao'
import { Campo } from '../../core/ui/Campo'
import { Cartao } from '../../core/ui/Cartao'
import { Carregando } from '../../core/ui/Carregando'
import { documentoValido, somenteDigitos } from '../../modules/pessoas/tipos'
import { useVincularPortal } from '../api'

function Layout({ titulo, subtitulo, children }: { titulo: string; subtitulo: string; children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-surface p-4">
      <div className="w-full max-w-sm">
        <div className="mb-6 text-center"><p className="text-xs font-semibold uppercase tracking-widest text-brand-600">Portal do cliente</p><h1 className="mt-2 text-2xl font-semibold">{titulo}</h1><p className="mt-1 text-sm text-ink-muted">{subtitulo}</p></div>
        <Cartao>{children}</Cartao>
      </div>
    </div>
  )
}

/** Usuário do portal já logado não vê login/cadastro; administrador logado vai para o ERP. */
function SoAnonimo({ children }: { children: React.ReactNode }) {
  const { sessao, carregando, usuario } = useAuth()
  if (carregando) return <Carregando telaCheia />
  if (sessao) return <Navigate to={usuario?.user_metadata?.portal === 'true' ? '/portal' : '/'} replace />
  return <>{children}</>
}

export function PortalLoginPage() {
  const { entrar } = useAuth()
  const navigate = useNavigate()
  const limite = useLimiteTentativas()
  const [email, setEmail] = useState(''); const [senha, setSenha] = useState(''); const [erro, setErro] = useState<string | null>(null); const [enviando, setEnviando] = useState(false)
  async function aoEnviar(e: FormEvent) {
    e.preventDefault(); if (limite.bloqueado) return
    setErro(null); setEnviando(true)
    try { await entrar(email.trim(), senha); limite.registrarSucesso(); navigate('/portal', { replace: true }) }
    catch (err) { limite.registrarFalha(); setErro(mensagemDeErro(err)) } finally { setEnviando(false) }
  }
  return (
    <SoAnonimo>
      <Layout titulo="Entrar" subtitulo="Acesse suas faturas, seu plano e o Indique e Ganhe">
        <form onSubmit={aoEnviar} className="space-y-4" noValidate>
          {erro && <Alerta tipo="erro">{erro}</Alerta>}
          {limite.mensagem && <Alerta tipo="info">{limite.mensagem}</Alerta>}
          <Campo rotulo="E-mail" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} />
          <Campo rotulo="Senha" type="password" autoComplete="current-password" value={senha} onChange={(e) => setSenha(e.target.value)} />
          <Botao type="submit" className="w-full" carregando={enviando} disabled={limite.bloqueado}>Entrar</Botao>
          <p className="text-center text-sm text-ink-muted"><Link to="/portal/recuperar" className="font-medium text-brand-600 hover:underline">Esqueci a senha</Link></p>
          <p className="text-center text-sm text-ink-muted">Primeiro acesso? <Link to="/portal/cadastro" className="font-medium text-brand-600 hover:underline">Criar meu acesso</Link></p>
        </form>
      </Layout>
    </SoAnonimo>
  )
}

export function PortalCadastroPage() {
  const { cadastrarPortal } = useAuth()
  const [email, setEmail] = useState(''); const [senha, setSenha] = useState(''); const [erro, setErro] = useState<string | null>(null); const [enviando, setEnviando] = useState(false); const [confirmar, setConfirmar] = useState(false)
  const navigate = useNavigate()
  async function aoEnviar(e: FormEvent) {
    e.preventDefault(); setErro(null)
    const v = validarSenha(senha); if (v.length) { setErro(v.join(' ')); return }
    setEnviando(true)
    try {
      const { precisaConfirmarEmail } = await cadastrarPortal(email.trim(), senha)
      if (precisaConfirmarEmail) setConfirmar(true); else navigate('/portal/vincular', { replace: true })
    } catch (err) { setErro(mensagemDeErro(err)) } finally { setEnviando(false) }
  }
  if (confirmar) return <Layout titulo="Confirme seu e-mail" subtitulo="Enviamos um link de confirmação"><Alerta tipo="sucesso">Abra o e-mail, clique no link e depois entre no portal para concluir o vínculo com o seu cadastro.</Alerta><p className="mt-4 text-center text-sm"><Link to="/portal/entrar" className="text-brand-600 hover:underline">Ir para o login</Link></p></Layout>
  return (
    <SoAnonimo>
      <Layout titulo="Criar meu acesso" subtitulo="Use o e-mail que você quiser. No próximo passo confirmamos seu CPF/CNPJ e telefone.">
        <form onSubmit={aoEnviar} className="space-y-4" noValidate>
          {erro && <Alerta tipo="erro">{erro}</Alerta>}
          <Campo rotulo="E-mail" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} />
          <Campo rotulo="Senha" type="password" autoComplete="new-password" value={senha} onChange={(e) => setSenha(e.target.value)} />
          <p className="text-xs text-ink-muted">Mínimo 8 caracteres com letra maiúscula, minúscula e número.</p>
          <Botao type="submit" className="w-full" carregando={enviando}>Continuar</Botao>
          <p className="text-center text-sm text-ink-muted">Já tem acesso? <Link to="/portal/entrar" className="font-medium text-brand-600 hover:underline">Entrar</Link></p>
        </form>
      </Layout>
    </SoAnonimo>
  )
}

export function PortalVincularPage() {
  const { sessao, carregando, usuario, sair } = useAuth()
  const vincular = useVincularPortal()
  const navigate = useNavigate()
  const [documento, setDocumento] = useState(''); const [telefone, setTelefone] = useState(''); const [erro, setErro] = useState<string | null>(null)
  if (carregando) return <Carregando telaCheia />
  if (!sessao) return <Navigate to="/portal/entrar" replace />
  if (usuario?.user_metadata?.portal !== 'true') return <Navigate to="/" replace />
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const doc = somenteDigitos(documento); const tel = somenteDigitos(telefone)
    if (!documentoValido(doc)) { setErro('CPF/CNPJ inválido.'); return }
    if (tel.length < 10) { setErro('Informe o telefone com DDD.'); return }
    setErro(null)
    vincular.mutate({ documento: doc, telefone: tel }, { onSuccess: () => navigate('/portal', { replace: true }) })
  }
  return (
    <Layout titulo="Confirme seu cadastro" subtitulo="Informe os dados que o provedor tem sobre você">
      <form onSubmit={aoEnviar} className="space-y-4" noValidate>
        {(erro || vincular.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(vincular.error)}</Alerta>}
        <Campo rotulo="CPF ou CNPJ" inputMode="numeric" value={documento} onChange={(e) => setDocumento(e.target.value)} placeholder="000.000.000-00" />
        <Campo rotulo="Telefone cadastrado (com DDD)" inputMode="tel" value={telefone} onChange={(e) => setTelefone(e.target.value)} placeholder="(11) 99999-9999" />
        <Botao type="submit" className="w-full" carregando={vincular.isPending}>Vincular ao meu cadastro</Botao>
        <button type="button" onClick={() => sair()} className="w-full text-center text-sm text-ink-muted hover:underline">Sair</button>
      </form>
    </Layout>
  )
}

export function PortalRecuperarPage() {
  const { recuperarSenha } = useAuth()
  const [email, setEmail] = useState(''); const [erro, setErro] = useState<string | null>(null); const [ok, setOk] = useState(false); const [enviando, setEnviando] = useState(false)
  async function aoEnviar(e: FormEvent) {
    e.preventDefault(); setErro(null); setEnviando(true)
    try { await recuperarSenha(email.trim(), `${window.location.origin}/portal/nova-senha`); setOk(true) } catch (err) { setErro(mensagemDeErro(err)) } finally { setEnviando(false) }
  }
  return (
    <Layout titulo="Recuperar senha" subtitulo="Enviamos um link para o seu e-mail">
      <form onSubmit={aoEnviar} className="space-y-4" noValidate>
        {erro && <Alerta tipo="erro">{erro}</Alerta>}
        {ok && <Alerta tipo="sucesso">Se o e-mail existir, você recebe um link para definir uma nova senha.</Alerta>}
        <Campo rotulo="E-mail" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        <Botao type="submit" className="w-full" carregando={enviando}>Enviar link</Botao>
        <p className="text-center text-sm"><Link to="/portal/entrar" className="text-brand-600 hover:underline">Voltar ao login</Link></p>
      </form>
    </Layout>
  )
}

export function PortalNovaSenhaPage() {
  const { definirSenha, sessao, carregando } = useAuth()
  const navigate = useNavigate()
  const [senha, setSenha] = useState(''); const [erro, setErro] = useState<string | null>(null); const [enviando, setEnviando] = useState(false)
  if (carregando) return <Carregando telaCheia />
  if (!sessao) return <Layout titulo="Link inválido" subtitulo="Abra o link do e-mail neste navegador"><p className="text-center text-sm"><Link to="/portal/recuperar" className="text-brand-600 hover:underline">Pedir novo link</Link></p></Layout>
  async function aoEnviar(e: FormEvent) {
    e.preventDefault(); const v = validarSenha(senha); if (v.length) { setErro(v.join(' ')); return }
    setErro(null); setEnviando(true)
    try { await definirSenha(senha); navigate('/portal', { replace: true }) } catch (err) { setErro(mensagemDeErro(err)) } finally { setEnviando(false) }
  }
  return (
    <Layout titulo="Nova senha" subtitulo="Escolha uma senha nova">
      <form onSubmit={aoEnviar} className="space-y-4" noValidate>
        {erro && <Alerta tipo="erro">{erro}</Alerta>}
        <Campo rotulo="Nova senha" type="password" autoComplete="new-password" value={senha} onChange={(e) => setSenha(e.target.value)} />
        <Botao type="submit" className="w-full" carregando={enviando}>Salvar senha</Botao>
      </form>
    </Layout>
  )
}
