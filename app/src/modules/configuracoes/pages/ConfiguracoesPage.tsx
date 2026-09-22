import { useState, type FormEvent } from 'react'
import { Link } from 'react-router'
import { useAuth } from '../../../core/auth/useAuth'
import { validarSenha } from '../../../core/auth/validarSenha'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Campo } from '../../../core/ui/Campo'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'

function Linha({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="flex justify-between gap-4 py-3 text-sm">
      <dt className="text-ink-muted">{rotulo}</dt>
      <dd className="font-medium">{valor}</dd>
    </div>
  )
}

function AlterarSenha() {
  const { definirSenha } = useAuth()
  const [senha, setSenha] = useState('')
  const [confirmacao, setConfirmacao] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [ok, setOk] = useState(false)
  const [enviando, setEnviando] = useState(false)

  async function aoEnviar(e: FormEvent) {
    e.preventDefault()
    setOk(false)
    const problemas = validarSenha(senha)
    if (problemas.length) { setErro(problemas.join(' ')); return }
    if (senha !== confirmacao) { setErro('As senhas não são iguais.'); return }
    setErro(null)
    setEnviando(true)
    try {
      await definirSenha(senha)
      setSenha(''); setConfirmacao(''); setOk(true)
    } catch (err) { setErro(mensagemDeErro(err)) } finally { setEnviando(false) }
  }

  return (
    <form onSubmit={aoEnviar} className="space-y-3" noValidate>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      {ok && <Alerta tipo="sucesso">Senha alterada.</Alerta>}
      <Campo rotulo="Nova senha" type="password" autoComplete="new-password" value={senha} onChange={(e) => setSenha(e.target.value)} placeholder="••••••••" />
      <Campo rotulo="Confirmar nova senha" type="password" autoComplete="new-password" value={confirmacao} onChange={(e) => setConfirmacao(e.target.value)} placeholder="••••••••" />
      <Botao type="submit" carregando={enviando}>Alterar senha</Botao>
    </form>
  )
}

export function ConfiguracoesPage() {
  const { usuario } = useAuth()
  const { organizacao } = useOrganizacao()
  return (
    <>
      <CabecalhoPagina titulo="Configurações" descricao="Dados da sua conta e da organização" />
      <div className="grid gap-6 md:grid-cols-2">
        <Cartao>
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Usuário</h2>
          <dl className="divide-y divide-line">
            <Linha rotulo="E-mail" valor={usuario?.email ?? '—'} />
            <Linha rotulo="Nome" valor={(usuario?.user_metadata?.nome as string | undefined) ?? '—'} />
          </dl>
        </Cartao>
        <Cartao>
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Organização</h2>
          <dl className="divide-y divide-line">
            <Linha rotulo="Nome" valor={organizacao.nome} />
            <Linha rotulo="Seu papel" valor={organizacao.papel === 'proprietario' ? 'Proprietário' : 'Membro'} />
          </dl>
        </Cartao>
        <Cartao className="md:col-span-2">
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Alterar senha</h2>
          <AlterarSenha />
        </Cartao>
        <Cartao className="md:col-span-2">
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Importação</h2>
          <p className="mb-3 text-sm text-ink-muted">Traga clientes, planos e contratos de um sistema anterior a partir de um arquivo CSV. A prévia mostra o que será criado antes de gravar.</p>
          <Link to="/configuracoes/importar" className="inline-flex h-10 items-center rounded-md bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">Importar CSV</Link>
        </Cartao>
        <Cartao className="md:col-span-2">
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Programa de pontos</h2>
          <p className="mb-3 text-sm text-ink-muted">Cadastre os prêmios da vitrine (foto, item do Estoque, preço) e confirme a entrega dos resgates.</p>
          <Link to="/configuracoes/pontos" className="inline-flex h-10 items-center rounded-md bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">Gerenciar prêmios</Link>
        </Cartao>
        <Cartao className="md:col-span-2">
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Parcerias</h2>
          <p className="mb-3 text-sm text-ink-muted">Clube de benefícios do Portal: importe a lista da Leveduca (CSV/XLSX) e cadastre acordos próprios da Servnet.</p>
          <Link to="/configuracoes/parcerias" className="inline-flex h-10 items-center rounded-md bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">Gerenciar parcerias</Link>
        </Cartao>
        <Cartao className="md:col-span-2">
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Integrações via API</h2>
          <p className="mb-3 text-sm text-ink-muted">Gere um token para um sistema de fora (ex.: Leveduca) consultar se um CPF é cliente ativo e qual o plano.</p>
          <Link to="/configuracoes/integracoes" className="inline-flex h-10 items-center rounded-md bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">Gerenciar tokens</Link>
        </Cartao>
      </div>
    </>
  )
}
