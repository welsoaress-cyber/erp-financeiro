import { Selecao } from '../../../core/ui/Selecao'
import { ROTULO_PESSOAL, type Negocio } from '../tipos'

interface Props {
  negocios: Negocio[]
  valor: string | null
  aoMudar: (id: string | null) => void
  /** id atual (edição): mantido na lista mesmo se inativo */
  atualId?: string | null
  rotulo?: string
  ajuda?: string
}

/** Select "Negócio" com a opção Pessoal (nulo). Lista negócios ativos e o atual. */
export function SelecaoNegocio({ negocios, valor, aoMudar, atualId, rotulo = 'Negócio', ajuda }: Props) {
  const opcoes = negocios.filter((n) => n.ativo || n.id === atualId).map((n) => ({ valor: n.id, rotulo: n.nome }))
  return (
    <Selecao
      rotulo={rotulo}
      opcoes={[{ valor: '', rotulo: ROTULO_PESSOAL }, ...opcoes]}
      value={valor ?? ''}
      onChange={(e) => aoMudar(e.target.value || null)}
      ajuda={ajuda}
    />
  )
}
