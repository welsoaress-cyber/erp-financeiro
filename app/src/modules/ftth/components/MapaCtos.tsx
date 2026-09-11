import { useEffect, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { buscarEndereco, CENTRO_PADRAO, COR_OCUPACAO, ocupacaoDe, type ClienteNoMapa, type CtoOcupacao } from '../tipos'

interface Props {
  ctos: CtoOcupacao[]
  clientes?: ClienteNoMapa[]
  altura?: string
  /** modo seleção: clique no mapa devolve a coordenada */
  aoClicarMapa?: (lat: number, lng: number) => void
  marcadorSelecao?: [number, number] | null
  aoClicarCto?: (cto: CtoOcupacao) => void
  comBusca?: boolean
  /** busca executada automaticamente ao abrir (ex.: endereço do cliente no cadastro) */
  buscaInicial?: string | null
  /** rota em desenho (vértices temporários a partir de uma âncora, ex.: a CTO) */
  desenho?: { ancora: [number, number]; pontos: [number, number][] } | null
  /** CTOs com chamado (OS) aberto: anel vermelho pulsante de alerta */
  ctosComChamado?: Set<string>
}

export function MapaCtos({ ctos, clientes = [], altura = '28rem', aoClicarMapa, marcadorSelecao, aoClicarCto, comBusca = false, buscaInicial = null, desenho = null, ctosComChamado }: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const mapa = useRef<L.Map | null>(null)
  const camada = useRef<L.LayerGroup | null>(null)
  const selecao = useRef<L.CircleMarker | null>(null)
  const pinoBusca = useRef<L.CircleMarker | null>(null)
  const cbClicar = useRef(aoClicarMapa)
  const cbCto = useRef(aoClicarCto)
  cbClicar.current = aoClicarMapa
  cbCto.current = aoClicarCto
  const [busca, setBusca] = useState('')
  const [buscando, setBuscando] = useState(false)
  const [erroBusca, setErroBusca] = useState<string | null>(null)

  useEffect(() => {
    if (!ref.current || mapa.current) return
    const m = L.map(ref.current).setView(CENTRO_PADRAO, 15)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '&copy; OpenStreetMap', maxZoom: 19 }).addTo(m)
    m.on('click', (e: L.LeafletMouseEvent) => cbClicar.current?.(Number(e.latlng.lat.toFixed(6)), Number(e.latlng.lng.toFixed(6))))
    camada.current = L.layerGroup().addTo(m)
    mapa.current = m
    return () => { m.remove(); mapa.current = null; camada.current = null; selecao.current = null; pinoBusca.current = null }
  }, [])

  // pinos, fios POP→CTO e clientes
  useEffect(() => {
    const m = mapa.current, g = camada.current
    if (!m || !g) return
    g.clearLayers()
    const porId = new Map(ctos.map((c) => [c.id, c]))
    for (const c of ctos) {
      if (c.tipo === 'cto' && c.pop_id) {
        const pop = porId.get(c.pop_id)
        if (pop) L.polyline([[pop.latitude, pop.longitude], ...(c.rota_pop ?? []), [c.latitude, c.longitude]], { color: '#2563eb', weight: 2, opacity: 0.6, dashArray: '6 4' }).addTo(g)
      }
    }
    for (const cl of clientes) {
      L.polyline([[cl.ctoLat, cl.ctoLng], ...(cl.rota ?? [[cl.lat, cl.lng] as [number, number]])], { color: '#0d9488', weight: 1.5, opacity: 0.7 }).addTo(g)
      const p = L.circleMarker([cl.lat, cl.lng], { radius: 5, color: '#0d9488', fillColor: '#14b8a6', fillOpacity: 0.9, weight: 1.5 })
      p.bindTooltip(`${cl.nome} · porta ${cl.porta}`)
      p.addTo(g)
    }
    for (const c of ctos) {
      if (c.tipo === 'pop') {
        const pin = L.circleMarker([c.latitude, c.longitude], { radius: 12, color: '#1d4ed8', fillColor: '#2563eb', fillOpacity: 0.9, weight: 3 })
        pin.bindTooltip(`${c.codigo} · POP (central)`)
        pin.on('click', () => cbCto.current?.(c))
        pin.addTo(g)
        continue
      }
      const { pct, tom } = ocupacaoDe(c)
      const emChamado = ctosComChamado?.has(c.id) ?? false
      if (emChamado) L.circleMarker([c.latitude, c.longitude], { radius: 16, color: '#dc2626', fillOpacity: 0, weight: 3, dashArray: '4 3' }).addTo(g)
      const cor = c.status !== 'ativa' ? '#6b7280' : COR_OCUPACAO[tom]
      const pin = L.circleMarker([c.latitude, c.longitude], { radius: 10, color: cor, fillColor: cor, fillOpacity: 0.85, weight: 2 })
      pin.bindTooltip(`${c.codigo} · ${pct}% (${c.ocupadas + c.reservadas}/${c.quantidade_portas})${c.com_defeito ? ` · ${c.com_defeito} defeito(s)` : ''}${emChamado ? ' · CHAMADO ABERTO' : ''}`)
      pin.on('click', () => cbCto.current?.(c))
      pin.addTo(g)
    }
    if (desenho) {
      const linha = [desenho.ancora, ...desenho.pontos]
      L.polyline(linha, { color: '#dc2626', weight: 2.5, opacity: 0.9, dashArray: '4 4' }).addTo(g)
      desenho.pontos.forEach((p, i) => L.circleMarker(p, { radius: i === desenho.pontos.length - 1 ? 6 : 4, color: '#dc2626', fillColor: '#ef4444', fillOpacity: 0.9 }).addTo(g))
    }
    if (ctos.length > 0 && !aoClicarMapa) {
      m.fitBounds(L.latLngBounds(ctos.map((c) => [c.latitude, c.longitude] as [number, number])).pad(0.2), { maxZoom: 16 })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ctos, clientes, desenho, ctosComChamado])

  useEffect(() => {
    const m = mapa.current
    if (!m) return
    if (selecao.current) { selecao.current.remove(); selecao.current = null }
    if (marcadorSelecao) {
      selecao.current = L.circleMarker(marcadorSelecao, { radius: 9, color: '#1d4ed8', fillColor: '#3b82f6', fillOpacity: 0.9 }).addTo(m)
      m.panTo(marcadorSelecao)
    }
  }, [marcadorSelecao])

  // endereço do cadastro: busca sozinho ao abrir (só dá zoom; sem marcar ponto)
  useEffect(() => {
    if (!buscaInicial || buscaInicial.trim().length < 3) return
    setBusca(buscaInicial)
    let cancelado = false
    void (async () => {
      const r = await buscarEndereco(buscaInicial.trim()).catch(() => null)
      const m = mapa.current
      if (cancelado || !r || !m) return
      m.setView([r.lat, r.lng], 18)
      if (pinoBusca.current) pinoBusca.current.remove()
      pinoBusca.current = L.circleMarker([r.lat, r.lng], { radius: 7, color: '#7c3aed', fillColor: '#8b5cf6', fillOpacity: 0.9 }).addTo(m)
    })()
    return () => { cancelado = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [buscaInicial])

  async function buscar() {
    if (busca.trim().length < 3 || buscando) return
    setBuscando(true); setErroBusca(null)
    try {
      const r = await buscarEndereco(busca.trim())
      const m = mapa.current
      if (!r || !m) { setErroBusca('Endereço não encontrado. Tente "rua, número, bairro, cidade".'); return }
      m.setView([r.lat, r.lng], 18)
      if (pinoBusca.current) pinoBusca.current.remove()
      pinoBusca.current = L.circleMarker([r.lat, r.lng], { radius: 7, color: '#7c3aed', fillColor: '#8b5cf6', fillOpacity: 0.9 }).addTo(m)
      pinoBusca.current.bindTooltip(r.rotulo.split(',').slice(0, 3).join(','))
      // no modo seleção, o resultado da busca já marca o ponto (clique no mapa ajusta depois)
      cbClicar.current?.(Number(r.lat.toFixed(6)), Number(r.lng.toFixed(6)))
    } catch {
      setErroBusca('Falha na busca de endereço (Nominatim fora do ar?).')
    } finally {
      setBuscando(false)
    }
  }

  return (
    <div className="space-y-2">
      {comBusca && (
        <div className="flex gap-2">
          <input
            type="search"
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); void buscar() } }}
            placeholder="Buscar endereço e dar zoom (ex.: Rua Pierre Bayle, 77, São Paulo)"
            className="h-10 flex-1 rounded-md border border-line bg-white px-3 text-sm outline-none focus:border-brand-600"
          />
          <button type="button" onClick={() => void buscar()} disabled={buscando} className="h-10 rounded-md bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700 disabled:opacity-50">{buscando ? 'Buscando…' : 'Buscar'}</button>
        </div>
      )}
      {erroBusca && <p className="text-xs text-red-600">{erroBusca}</p>}
      {/* z-0 cria um contexto de empilhamento próprio: os panes internos do Leaflet (z-index 200–700) não furam o modal */}
      <div ref={ref} style={{ height: altura }} className="relative z-0 w-full rounded-md border border-line" />
    </div>
  )
}
