export type StatusCto = 'ativa' | 'manutencao' | 'desativada'
export const ROTULO_STATUS_CTO: Record<StatusCto, string> = { ativa: 'Ativa', manutencao: 'Manutenção', desativada: 'Desativada' }

export type StatusPorta = 'livre' | 'ocupada' | 'reservada'

export type TipoPontoRede = 'cto' | 'pop'

export interface Cto {
  id: string
  organizacao_id: string
  negocio_id: string
  tipo: TipoPontoRede
  pop_id: string | null
  rota_pop: [number, number][] | null
  codigo: string
  lacre: string | null
  endereco: string | null
  referencia: string | null
  latitude: number
  longitude: number
  quantidade_portas: number
  splitter: string | null
  status: StatusCto
  observacao: string | null
}

export interface CtoOcupacao extends Cto {
  ocupadas: number
  reservadas: number
  livres: number
  com_defeito: number
  drops_disponiveis: number
}

export interface CtoPorta {
  id: string
  cto_id: string
  numero: number
  status: StatusPorta
  defeito: boolean
  drop_disponivel: boolean
  pessoa_id: string | null
  contrato_id: string | null
  data_ocupacao: string | null
  observacao: string | null
  cliente_latitude: number | null
  cliente_longitude: number | null
  rota_cliente: [number, number][] | null
  lacre: string | null
}

/** Ponto de cliente ligado a uma CTO (fio CTO→cliente no mapa). */
export interface ClienteNoMapa { lat: number; lng: number; nome: string; ctoLat: number; ctoLng: number; porta: number; rota: [number, number][] | null }

/** Busca de endereço (Nominatim/OpenStreetMap, gratuito, ~1 req/s). */
export async function buscarEndereco(q: string): Promise<{ lat: number; lng: number; rotulo: string } | null> {
  const url = `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=br&q=${encodeURIComponent(q)}`
  const res = await fetch(url, { headers: { Accept: 'application/json' } })
  if (!res.ok) return null
  const lista = (await res.json()) as { lat: string; lon: string; display_name: string }[]
  const r = lista[0]
  return r ? { lat: Number(r.lat), lng: Number(r.lon), rotulo: r.display_name } : null
}

export type EventoPorta = 'ocupacao' | 'reserva' | 'liberacao' | 'troca' | 'defeito' | 'reparo'
export const ROTULO_EVENTO: Record<EventoPorta, string> = {
  ocupacao: 'Ocupação', reserva: 'Reserva', liberacao: 'Liberação', troca: 'Troca', defeito: 'Defeito', reparo: 'Reparo',
}

export interface CtoHistorico {
  id: string
  cto_id: string
  porta_id: string
  evento: EventoPorta
  pessoa_id: string | null
  contrato_id: string | null
  observacao: string | null
  criado_em: string
}

export interface DadosCto {
  negocio_id: string
  tipo: TipoPontoRede
  pop_id: string | null
  codigo: string
  lacre: string | null
  endereco: string | null
  referencia: string | null
  latitude: number
  longitude: number
  quantidade_portas: number
  splitter: string | null
  status: StatusCto
  observacao: string | null
}

/** Ocupação em % (ocupadas + reservadas sobre o total) e o tom do alerta ao vivo. */
export function ocupacaoDe(c: CtoOcupacao): { pct: number; tom: 'ok' | 'quase' | 'lotada' } {
  const usadas = c.ocupadas + c.reservadas
  const pct = c.quantidade_portas > 0 ? Math.round((usadas / c.quantidade_portas) * 100) : 0
  return { pct, tom: pct >= 100 ? 'lotada' : pct >= 90 ? 'quase' : 'ok' }
}

export const COR_OCUPACAO = { ok: '#15803d', quase: '#d97706', lotada: '#b91c1c' } as const

/** Base do mapa: Jd. Moraes Prado, São Paulo/SP. */
export const CENTRO_PADRAO: [number, number] = [-23.4903, -46.4142]
