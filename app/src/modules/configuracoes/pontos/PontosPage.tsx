import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { useNegocios } from '../../negocios/api'
import { VitrinePontosAdmin } from '../../portal/components/VitrinePontosAdmin'

/** Cadastro dos prêmios do programa de pontos por pontualidade e confirmação de entrega. */
export function PontosPage() {
  const negocios = useNegocios()
  const [negocioSel, setNegocioSel] = useState('')
  const ativos = useMemo(() => (negocios.data ?? []).filter((n) => n.ativo), [negocios.data])
  const negocio = ativos.find((n) => n.id === negocioSel) ?? ativos[0] ?? null
  if (negocios.isPending) return <><CabecalhoPagina titulo="Programa de pontos" /><Carregando /></>
  return (
    <>
      <CabecalhoPagina titulo="Programa de pontos" descricao="Cliente ganha pontos pagando a fatura antes do vencimento — cadastre os prêmios da vitrine aqui."
        acoes={ativos.length > 1 && negocio ? (
          <select aria-label="Negócio" value={negocio.id} onChange={(e) => setNegocioSel(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
            {ativos.map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
          </select>
        ) : undefined} />
      {!negocio && <Alerta tipo="info">Cadastre um negócio ativo antes.</Alerta>}
      {negocio && (
        <div className="space-y-4">
          <Alerta tipo="info">Regra ativa: campanha de 01/10/2026 a 30/09/2027. Ligue "Pontos por pontualidade" em Notificações para o negócio começar a pontuar. Desconto em fatura (R$ 0,25/ponto) é resgatado pelo próprio cliente no Portal, sem cadastro — não precisa de nada aqui.</Alerta>
          <VitrinePontosAdmin negocioId={negocio.id} />
        </div>
      )}
    </>
  )
}
