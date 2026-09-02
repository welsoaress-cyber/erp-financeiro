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
      </div>
    </>
  )
}
