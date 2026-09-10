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
