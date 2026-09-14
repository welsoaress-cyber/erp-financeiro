import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { CentroCusto, DadosCentroCusto } from './tipos'

export const chaveCentros = (org: string) => ['centros_custo', org] as const

export function useCentrosCusto() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chaveCentros(organizacao.id),
    queryFn: async (): Promise<CentroCusto[]> => {
      const { data, error } = await supabase.from('centros_custo').select('*').eq('organizacao_id', organizacao.id).order('nome')
      if (error) throw error
      return (data ?? []) as CentroCusto[]
    },
  })
}

/** Gasto do mês por centro (realizado + previsto), para a lista. */
export interface GastoCentro { centro_custo_id: string | null; negocio_id: string | null; status: string; valor: number }
export function useGastosCentros(mes: string) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveCentros(organizacao.id), 'gastos', mes],
    queryFn: async (): Promise<GastoCentro[]> => {
      const { data, error } = await supabase.from('vw_rel_gastos_centro_custo').select('centro_custo_id, negocio_id, status, valor').eq('organizacao_id', organizacao.id).eq('mes', mes)
      if (error) throw error
      return (data ?? []).map((g) => ({ ...g, valor: Number(g.valor) })) as GastoCentro[]
    },
  })
}

export function useCriarCentroCusto() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (d: DadosCentroCusto) => {
      const { data, error } = await supabase.from('centros_custo').insert({ ...d, organizacao_id: organizacao.id }).select().single()
      if (error) throw error
      return data as CentroCusto
    },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: chaveCentros(organizacao.id) }) },
  })
}

export function useAtualizarCentroCusto() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, ...d }: DadosCentroCusto & { id: string }) => {
      const { data, error } = await supabase.from('centros_custo').update(d).eq('id', id).select().single()
      if (error) throw error
      return data as CentroCusto
    },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: chaveCentros(organizacao.id) }) },
  })
}
