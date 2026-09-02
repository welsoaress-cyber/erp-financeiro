import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { Categoria, DadosCategoria } from './tipos'

const chave = (organizacaoId: string) => ['categorias', organizacaoId] as const

export function useCategorias() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chave(organizacao.id),
    queryFn: async (): Promise<Categoria[]> => {
      const { data, error } = await supabase
        .from('categorias')
        .select('*')
        .eq('organizacao_id', organizacao.id)
        .order('nome')
      if (error) throw error
      return data ?? []
    },
  })
}

export function useCriarCategoria() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (dados: DadosCategoria): Promise<Categoria> => {
      const { data, error } = await supabase
        .from('categorias')
        .insert({ ...dados, nome: dados.nome.trim(), organizacao_id: organizacao.id })
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: chave(organizacao.id) }),
  })
}

export function useAtualizarCategoria() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    // tipo nunca é enviado: o banco também rejeita, mas a UI não tenta.
    mutationFn: async ({ id, ...dados }: Omit<DadosCategoria, 'tipo'> & { id: string }): Promise<Categoria> => {
      const { data, error } = await supabase
        .from('categorias')
        .update({ ...dados, nome: dados.nome.trim() })
        .eq('id', id)
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: chave(organizacao.id) }),
  })
}
