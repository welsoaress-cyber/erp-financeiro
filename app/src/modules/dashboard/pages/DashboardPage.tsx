import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'

export function DashboardPage() {
  const { organizacao } = useOrganizacao()
  return (
    <>
      <CabecalhoPagina titulo="Dashboard" descricao={`Visão geral de ${organizacao.nome}`} />
      <Cartao className="flex flex-col items-center gap-2 py-16 text-center">
        <p className="text-sm font-medium">Fundação concluída</p>
        <p className="text-sm text-ink-muted">Os indicadores financeiros serão exibidos aqui a partir da Etapa 6.</p>
      </Cartao>
    </>
  )
}
