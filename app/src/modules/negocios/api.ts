import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { DadosNegocio, Negocio } from './tipos'

export const chaveNegocios = (organizacaoId: string) => ['negocios', organizacaoId] as const

export function useNegocios() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chaveNegocios(organizacao.id),
    queryFn: async (): Promise<Negocio[]> => {
      const { data, error } = await supabase
        .from('negocios')
        .select('*')
        .eq('organizacao_id', organizacao.id)
        .order('ativo', { ascending: false })
        .order('nome')
      if (error) throw error
      return data ?? []
    },
  })
}

export function useCriarNegocio() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (dados: DadosNegocio) => {
      const { data, error } = await supabase
        .from('negocios')
        .insert({ ...dados, nome: dados.nome.trim(), organizacao_id: organizacao.id })
        .select()
        .single()
      if (error) throw error
      return data as Negocio
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: chaveNegocios(organizacao.id) }),
  })
}

export function useAtualizarNegocio() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, ...dados }: DadosNegocio & { id: string }) => {
      const { data, error } = await supabase
        .from('negocios')
        .update({ ...dados, nome: dados.nome.trim() })
        .eq('id', id)
        .select()
        .single()
      if (error) throw error
      return data as Negocio
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: chaveNegocios(organizacao.id) })
      void qc.invalidateQueries({ queryKey: ['dashboard', organizacao.id] })
    },
  })
}
