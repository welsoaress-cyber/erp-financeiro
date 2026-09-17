import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../../core/supabase/client'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'

export interface ApiToken {
  id: string
  organizacao_id: string
  negocio_id: string
  negocio: string
  nome: string
  token_prefixo: string
  ativo: boolean
  criado_em: string
  revogado_em: string | null
  ultimo_uso_em: string | null
  consultas: number
}

const chave = (org: string) => ['api-tokens', org] as const

export function useApiTokens() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chave(organizacao.id),
    queryFn: async (): Promise<ApiToken[]> => {
      const { data, error } = await supabase.from('vw_api_tokens').select('*').eq('organizacao_id', organizacao.id).order('criado_em', { ascending: false })
      if (error) throw error
      return data ?? []
    },
  })
}

export function useCriarApiToken() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (p: { negocio_id: string; nome: string }) => {
      const { data, error } = await supabase.rpc('criar_api_token', { p_negocio_id: p.negocio_id, p_nome: p.nome })
      if (error) throw error
      return (data as { token_id: string; token: string; token_prefixo: string }[])[0]
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: chave(organizacao.id) }),
  })
}

export function useRevogarApiToken() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('revogar_api_token', { p_id: id })
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: chave(organizacao.id) }),
  })
}
