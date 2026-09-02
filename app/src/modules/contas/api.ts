import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { Conta, DadosConta } from './tipos'

const chave = (organizacaoId: string) => ['contas', organizacaoId] as const

export function useContas() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chave(organizacao.id),
    queryFn: async (): Promise<Conta[]> => {
      const { data, error } = await supabase
        .from('contas')
        .select('*')
        .eq('organizacao_id', organizacao.id)
        .order('ativo', { ascending: false })
        .order('nome')
      if (error) throw error
      return data ?? []
    },
  })
}

export function useCriarConta() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (dados: DadosConta): Promise<Conta> => {
      const { data, error } = await supabase
        .from('contas')
        .insert({ ...dados, nome: dados.nome.trim(), organizacao_id: organizacao.id })
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: chave(organizacao.id) }),
  })
}

export function useAtualizarConta() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    // tipo nunca é enviado: o banco também rejeita, mas a UI não tenta.
    mutationFn: async ({ id, ...dados }: Omit<DadosConta, 'tipo'> & { id: string }): Promise<Conta> => {
      const { data, error } = await supabase
        .from('contas')
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
