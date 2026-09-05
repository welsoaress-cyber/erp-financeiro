import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { Lancamento } from '../lancamentos/tipos'
import type { CartaoConfig, Fatura } from './tipos'

const chave = (org: string) => ['cartoes', org] as const

export function useCartoesConfig() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'config'],
    queryFn: async (): Promise<CartaoConfig[]> => {
      const { data, error } = await supabase.from('cartoes_config').select('*').eq('organizacao_id', organizacao.id)
      if (error) throw error
      return (data ?? []) as CartaoConfig[]
    },
  })
}

function useInvalidarCartoes() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => {
    void qc.invalidateQueries({ queryKey: chave(organizacao.id) })
    void qc.invalidateQueries({ queryKey: ['contas', organizacao.id] })
    void qc.invalidateQueries({ queryKey: ['lancamentos', organizacao.id] })
  }
}

export function useSalvarCartaoConfig() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidarCartoes()
  return useMutation({
    mutationFn: async (d: { id?: string; conta_id: string; dia_fechamento: number; dia_vencimento: number; limite_total: number }) => {
      const q = d.id
        ? supabase.from('cartoes_config').update({ dia_fechamento: d.dia_fechamento, dia_vencimento: d.dia_vencimento, limite_total: d.limite_total }).eq('id', d.id)
        : supabase.from('cartoes_config').insert({ conta_id: d.conta_id, dia_fechamento: d.dia_fechamento, dia_vencimento: d.dia_vencimento, limite_total: d.limite_total, organizacao_id: organizacao.id })
      const { data, error } = await q.select().single()
      if (error) throw error
      return data as CartaoConfig
    },
    onSuccess: invalidar,
  })
}

export function useFaturas() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'faturas'],
    queryFn: async (): Promise<Fatura[]> => {
      const { data, error } = await supabase
        .from('faturas')
        .select('*')
        .eq('organizacao_id', organizacao.id)
        .order('periodo_fim', { ascending: false })
      if (error) throw error
      return (data ?? []).map((f) => ({ ...f, valor_total: Number(f.valor_total), valor_pago: Number(f.valor_pago) })) as Fatura[]
    },
  })
}

/** Lançamentos que compõem uma fatura. */
export function useItensFatura(faturaId: string | null) {
  return useQuery({
    queryKey: ['cartoes', 'itens', faturaId],
    enabled: Boolean(faturaId),
    queryFn: async (): Promise<Lancamento[]> => {
      const { data: itens, error } = await supabase.from('fatura_itens').select('lancamento_id').eq('fatura_id', faturaId!)
      if (error) throw error
      const ids = (itens ?? []).map((i) => i.lancamento_id)
      if (ids.length === 0) return []
      const { data, error: e2 } = await supabase.from('lancamentos').select('*').in('id', ids).order('data_efetivacao')
      if (e2) throw e2
      return (data ?? []) as Lancamento[]
    },
  })
}

export function usePagarFatura() {
  const invalidar = useInvalidarCartoes()
  return useMutation({
    mutationFn: async ({ faturaId, contaOrigemId, valor, data }: { faturaId: string; contaOrigemId: string; valor: number | null; data: string }) => {
      const { data: f, error } = await supabase.rpc('pagar_fatura', { p_fatura: faturaId, p_conta_origem: contaOrigemId, p_valor: valor, p_data: data })
      if (error) throw error
      return f as Fatura
    },
    onSuccess: invalidar,
  })
}

export function useFecharFaturasAgora() {
  const invalidar = useInvalidarCartoes()
  return useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc('fechar_faturas_agora')
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}
