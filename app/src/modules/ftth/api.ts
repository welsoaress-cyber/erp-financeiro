import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { Cto, CtoHistorico, CtoOcupacao, CtoPorta, DadosCto } from './tipos'

const chave = (org: string) => ['ftth', org] as const

export function useCtos() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'ctos'],
    queryFn: async (): Promise<CtoOcupacao[]> => {
      const { data, error } = await supabase.from('vw_ctos_ocupacao').select('*').eq('organizacao_id', organizacao.id).order('codigo')
      if (error) throw error
      return (data ?? []).map((c) => ({ ...c, latitude: Number(c.latitude), longitude: Number(c.longitude), ocupadas: Number(c.ocupadas), reservadas: Number(c.reservadas), livres: Number(c.livres), com_defeito: Number(c.com_defeito), drops_disponiveis: Number(c.drops_disponiveis) })) as CtoOcupacao[]
    },
  })
}

function useInvalidarFtth() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => void qc.invalidateQueries({ queryKey: chave(organizacao.id) })
}

export function useSalvarCto() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidarFtth()
  return useMutation({
    mutationFn: async (d: DadosCto & { id?: string }) => {
      const { id, ...dados } = d
      const q = id
        ? supabase.from('ctos').update(dados).eq('id', id)
        : supabase.from('ctos').insert({ ...dados, organizacao_id: organizacao.id })
      const { data, error } = await q.select().single()
      if (error) throw error
      return data as Cto
    },
    onSuccess: invalidar,
  })
}

export function usePortasCto(ctoId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'portas', ctoId],
    enabled: Boolean(ctoId),
    queryFn: async (): Promise<CtoPorta[]> => {
      const { data, error } = await supabase.from('cto_portas').select('*').eq('cto_id', ctoId!).order('numero')
      if (error) throw error
      return (data ?? []) as CtoPorta[]
    },
  })
}

export function useHistoricoCto(ctoId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'historico', ctoId ?? 'todos'],
    queryFn: async (): Promise<CtoHistorico[]> => {
      let q = supabase.from('cto_historico').select('*').eq('organizacao_id', organizacao.id).order('criado_em', { ascending: false }).limit(100)
      if (ctoId) q = q.eq('cto_id', ctoId)
      const { data, error } = await q
      if (error) throw error
      return (data ?? []) as CtoHistorico[]
    },
  })
}

/** Portas ocupadas/reservadas com localização do cliente (fios CTO→cliente no mapa). */
export function useClientesMapa() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'clientes-mapa'],
    queryFn: async (): Promise<CtoPorta[]> => {
      const { data, error } = await supabase.from('cto_portas').select('*').eq('organizacao_id', organizacao.id).not('cliente_latitude', 'is', null)
      if (error) throw error
      return (data ?? []).map((p) => ({ ...p, cliente_latitude: Number(p.cliente_latitude), cliente_longitude: Number(p.cliente_longitude) })) as CtoPorta[]
    },
  })
}

export function useLocalClientePorta() {
  const invalidar = useInvalidarFtth()
  return useMutation({
    mutationFn: async (d: { porta_id: string; latitude: number; longitude: number }) => {
      const { data, error } = await supabase.rpc('local_cliente_porta', { p_porta_id: d.porta_id, p_latitude: d.latitude, p_longitude: d.longitude })
      if (error) throw error
      return data as CtoPorta
    },
    onSuccess: invalidar,
  })
}

/** Vértices do fio POP→CTO (traçado real). */
export function useRotaPop() {
  const invalidar = useInvalidarFtth()
  return useMutation({
    mutationFn: async (d: { cto_id: string; rota: [number, number][] }) => {
      const { data, error } = await supabase.rpc('rota_pop_cto', { p_cto_id: d.cto_id, p_rota: d.rota })
      if (error) throw error
      return data as Cto
    },
    onSuccess: invalidar,
  })
}

/** Vértices do fio CTO→cliente (o último ponto é o local do cliente). */
export function useRotaCliente() {
  const invalidar = useInvalidarFtth()
  return useMutation({
    mutationFn: async (d: { porta_id: string; rota: [number, number][] }) => {
      const { data, error } = await supabase.rpc('rota_cliente_porta', { p_porta_id: d.porta_id, p_rota: d.rota })
      if (error) throw error
      return data as CtoPorta
    },
    onSuccess: invalidar,
  })
}

/** Lacre numerado do drop dentro da CTO (único na organização; vazio remove). */
export function useLacrePorta() {
  const invalidar = useInvalidarFtth()
  return useMutation({
    mutationFn: async (d: { porta_id: string; lacre: string }) => {
      const { data, error } = await supabase.rpc('lacre_porta_cto', { p_porta_id: d.porta_id, p_lacre: d.lacre })
      if (error) throw error
      return data as CtoPorta
    },
    onSuccess: invalidar,
  })
}

export function useVincularPorta() {
  const invalidar = useInvalidarFtth()
  return useMutation({
    mutationFn: async (d: { porta_id: string; pessoa_id: string; contrato_id: string; reservar?: boolean; observacao?: string | null }) => {
      const { data, error } = await supabase.rpc('vincular_porta_cto', { p_porta_id: d.porta_id, p_pessoa_id: d.pessoa_id, p_contrato_id: d.contrato_id, p_reservar: d.reservar ?? false, p_observacao: d.observacao ?? null })
      if (error) throw error
      return data as CtoPorta
    },
    onSuccess: invalidar,
  })
}

export function useLiberarPorta() {
  const invalidar = useInvalidarFtth()
  return useMutation({
    mutationFn: async (d: { porta_id: string; observacao?: string | null }) => {
      const { data, error } = await supabase.rpc('liberar_porta_cto', { p_porta_id: d.porta_id, p_observacao: d.observacao ?? null })
      if (error) throw error
      return data as CtoPorta
    },
    onSuccess: invalidar,
  })
}

export function useTrocarPorta() {
  const invalidar = useInvalidarFtth()
  return useMutation({
    mutationFn: async (d: { origem_id: string; destino_id: string; observacao?: string | null }) => {
      const { data, error } = await supabase.rpc('trocar_porta_cto', { p_porta_origem: d.origem_id, p_porta_destino: d.destino_id, p_observacao: d.observacao ?? null })
      if (error) throw error
      return data as CtoPorta
    },
    onSuccess: invalidar,
  })
}

export function useDefeitoPorta() {
  const invalidar = useInvalidarFtth()
  return useMutation({
    mutationFn: async (d: { porta_id: string; defeito: boolean; observacao?: string | null }) => {
      const { data, error } = await supabase.rpc('defeito_porta_cto', { p_porta_id: d.porta_id, p_defeito: d.defeito, p_observacao: d.observacao ?? null })
      if (error) throw error
      return data as CtoPorta
    },
    onSuccess: invalidar,
  })
}

export interface PontoAbaixo { id: string; codigo: string; tipo: string; nivel: number; clientes: number }

/** Tudo que é alimentado por um POP/CEO (impacto de rompimento). */
export function useAbaixoDe(pontoId: string | null) {
  return useQuery({
    queryKey: ['ftth-abaixo', pontoId ?? 'x'],
    enabled: pontoId !== null,
    queryFn: async (): Promise<PontoAbaixo[]> => {
      const { data, error } = await supabase.rpc('ftth_abaixo_de', { p_ponto_id: pontoId! })
      if (error) throw error
      return (data ?? []).map((p: PontoAbaixo) => ({ ...p, clientes: Number(p.clientes) }))
    },
  })
}

export interface OltStatus { pop_id: string; online: boolean; latencia_ms: number | null; ultima_verificacao: string; mudou_em: string }

export function useOltStatus() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: ['olt-status', organizacao.id],
    refetchInterval: 120_000,
    queryFn: async (): Promise<OltStatus[]> => {
      const { data, error } = await supabase.from('olt_status').select('pop_id, online, latencia_ms, ultima_verificacao, mudou_em').eq('organizacao_id', organizacao.id)
      if (error) throw error
      return (data ?? []) as OltStatus[]
    },
  })
}
