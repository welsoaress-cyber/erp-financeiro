import { useEffect, useRef } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { CENTRO_PADRAO, COR_OCUPACAO, ocupacaoDe, type CtoOcupacao } from '../tipos'

interface Props {
  ctos: CtoOcupacao[]
  altura?: string
  /** modo seleção: clique no mapa devolve a coordenada (cadastro de CTO) */
  aoClicarMapa?: (lat: number, lng: number) => void
  marcadorSelecao?: [number, number] | null
  aoClicarCto?: (cto: CtoOcupacao) => void
}

export function MapaCtos({ ctos, altura = '28rem', aoClicarMapa, marcadorSelecao, aoClicarCto }: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const mapa = useRef<L.Map | null>(null)
  const camada = useRef<L.LayerGroup | null>(null)
  const selecao = useRef<L.Marker | null>(null)
  const cbClicar = useRef(aoClicarMapa)
  const cbCto = useRef(aoClicarCto)
  cbClicar.current = aoClicarMapa
  cbCto.current = aoClicarCto

  useEffect(() => {
    if (!ref.current || mapa.current) return
    const m = L.map(ref.current).setView(CENTRO_PADRAO, 14)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap',
      maxZoom: 19,
    }).addTo(m)
    m.on('click', (e: L.LeafletMouseEvent) => cbClicar.current?.(Number(e.latlng.lat.toFixed(6)), Number(e.latlng.lng.toFixed(6))))
    camada.current = L.layerGroup().addTo(m)
    mapa.current = m
    return () => { m.remove(); mapa.current = null; camada.current = null; selecao.current = null }
  }, [])

  // pinos das CTOs (cor pela ocupação)
  useEffect(() => {
    const m = mapa.current, g = camada.current
    if (!m || !g) return
    g.clearLayers()
    for (const c of ctos) {
      const { pct, tom } = ocupacaoDe(c)
      const cor = c.status !== 'ativa' ? '#6b7280' : COR_OCUPACAO[tom]
      const marcador = L.circleMarker([c.latitude, c.longitude], { radius: 10, color: cor, fillColor: cor, fillOpacity: 0.85, weight: 2 })
      marcador.bindTooltip(`${c.codigo} · ${pct}% (${c.ocupadas + c.reservadas}/${c.quantidade_portas})${c.com_defeito ? ` · ${c.com_defeito} defeito(s)` : ''}`)
      marcador.on('click', () => cbCto.current?.(c))
      marcador.addTo(g)
    }
    if (ctos.length > 0 && !aoClicarMapa) {
      m.fitBounds(L.latLngBounds(ctos.map((c) => [c.latitude, c.longitude] as [number, number])).pad(0.2), { maxZoom: 16 })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ctos])

  // marcador de seleção (cadastro)
  useEffect(() => {
    const m = mapa.current
    if (!m) return
    if (selecao.current) { selecao.current.remove(); selecao.current = null }
    if (marcadorSelecao) {
      selecao.current = L.circleMarker(marcadorSelecao, { radius: 9, color: '#1d4ed8', fillColor: '#3b82f6', fillOpacity: 0.9 }) as unknown as L.Marker
      ;(selecao.current as unknown as L.CircleMarker).addTo(m)
      m.panTo(marcadorSelecao)
    }
  }, [marcadorSelecao])

  return <div ref={ref} style={{ height: altura }} className="w-full rounded-md border border-line" />
}
