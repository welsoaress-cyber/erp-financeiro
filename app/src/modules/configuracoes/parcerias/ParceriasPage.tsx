import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { useNegocios } from '../../negocios/api'
import { ParceriasAdmin } from '../../portal/components/ParceriasAdmin'

/** Clube de benefícios do Portal: importação da lista da Leveduca + parceiros próprios da Servnet. */
export function ParceriasPage() {
  const negocios = useNegocios()
  const [negocioSel, setNegocioSel] = useState('')
  const ativos = useMemo(() => (negocios.data ?? []).filter((n) => n.ativo), [negocios.data])
  const negocio = ativos.find((n) => n.id === negocioSel) ?? ativos[0] ?? null
  if (negocios.isPending) return <><CabecalhoPagina titulo="Parcerias" /><Carregando /></>
  return (
    <>
      <CabecalhoPagina titulo="Parcerias" descricao="Clube de benefícios que aparece no Portal do cliente — lista da Leveduca + acordos próprios da Servnet."
        acoes={ativos.length > 1 && negocio ? (
          <select aria-label="Negócio" value={negocio.id} onChange={(e) => setNegocioSel(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
            {ativos.map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
          </select>
        ) : undefined} />
      {!negocio && <Alerta tipo="info">Cadastre um negócio ativo antes.</Alerta>}
      {negocio && <ParceriasAdmin negocioId={negocio.id} />}
    </>
  )
}
