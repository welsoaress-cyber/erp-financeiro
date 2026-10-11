import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'

/** Voto de confiança (etapa 47): o cliente prometeu pagar até a data, e o bloqueio fica segurado até lá.
 *  Mesma chave de cache da tela Cobrança — dar/cancelar em Contas a receber reflete lá na hora e vice-versa. */
export interface Confianca {
  id: string
  negocio_id: string | null
  contrato_id: string | null
  lancamento_id: string | null
  pessoa_id: string
  segurar_ate: string
  observacao: string | null
  status: 'ativa' | 'cumprida' | 'furada' | 'cancelada'
}

const chave = (org: string) => ['cobranca', org] as const

export function useConfiancasAtivas(habilitado = true) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    enabled: habilitado,
    queryKey: [...chave(organizacao.id), 'confiancas'],
    queryFn: async (): Promise<Confianca[]> => {
      const { data, error } = await supabase.from('confiancas')
        .select('id, negocio_id, contrato_id, lancamento_id, pessoa_id, segurar_ate, observacao, status')
        .eq('organizacao_id', organizacao.id).eq('status', 'ativa').order('segurar_ate')
      if (error) throw error
      return (data ?? []) as Confianca[]
    },
  })
}

function useInvalidarConfiancas() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => {
    void qc.invalidateQueries({ queryKey: chave(organizacao.id) })
    void qc.invalidateQueries({ queryKey: ['contratos', organizacao.id] })
  }
}

export function useDarConfianca() {
  const invalidar = useInvalidarConfiancas()
  return useMutation({
    mutationFn: async (p: { contratoId: string; segurarAte: string; observacao: string | null } | { lancamentoId: string; segurarAte: string; observacao: string | null }) => {
      const { error } = 'contratoId' in p
        ? await supabase.rpc('dar_confianca', { p_contrato_id: p.contratoId, p_segurar_ate: p.segurarAte, p_observacao: p.observacao })
        : await supabase.rpc('dar_confianca_lancamento', { p_lancamento_id: p.lancamentoId, p_segurar_ate: p.segurarAte, p_observacao: p.observacao })
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}

export function useCancelarConfianca() {
  const invalidar = useInvalidarConfiancas()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('cancelar_confianca', { p_id: id })
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}
