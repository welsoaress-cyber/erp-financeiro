import { Link } from 'react-router'
import { useAuth } from '../../../core/auth/useAuth'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'

function Linha({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="flex justify-between gap-4 py-3 text-sm">
      <dt className="text-ink-muted">{rotulo}</dt>
      <dd className="font-medium">{valor}</dd>
    </div>
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
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Importação</h2>
          <p className="mb-3 text-sm text-ink-muted">Traga clientes, planos e contratos de um sistema anterior a partir de um arquivo CSV. A prévia mostra o que será criado antes de gravar.</p>
          <Link to="/configuracoes/importar" className="inline-flex h-10 items-center rounded-md bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">Importar CSV</Link>
        </Cartao>
      </div>
    </>
  )
}
