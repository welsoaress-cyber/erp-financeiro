import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import { fimDoMes } from '../../core/formatos'
import type { DadosLancamento, Lancamento } from './tipos'

export const chaveLancamentos = (organizacaoId: string) => ['lancamentos', organizacaoId] as const

/** Lançamentos do mês (por data de competência), mais recentes primeiro. */
export function useLancamentos(mes: string) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveLancamentos(organizacao.id), mes],
    queryFn: async (): Promise<Lancamento[]> => {
      const { data, error } = await supabase
        .from('lancamentos')
        .select('*')
        .eq('organizacao_id', organizacao.id)
        .gte('data_competencia', mes)
        .lte('data_competencia', fimDoMes(mes))
        .order('data_competencia', { ascending: false })
        .order('criado_em', { ascending: false })
      if (error) throw error
      return data ?? []
    },
  })
}

/** Possíveis duplicados: mesma conta, mesmo valor, data ±1 dia, não cancelados. */
export async function buscarPossiveisDuplicados(organizacaoId: string, d: DadosLancamento, ignorarId?: string): Promise<Lancamento[]> {
  const base = new Date(`${d.data_competencia}T00:00:00Z`)
  const dia = (n: number) => new Date(base.getTime() + n * 86_400_000).toISOString().slice(0, 10)
  let q = supabase
    .from('lancamentos')
    .select('*')
    .eq('organizacao_id', organizacaoId)
    .eq('conta_id', d.conta_id)
    .eq('valor', d.valor)
    .neq('status', 'cancelado')
    .gte('data_competencia', dia(-1))
    .lte('data_competencia', dia(1))
  if (ignorarId) q = q.neq('id', ignorarId)
  const { data, error } = await q
  if (error) throw error
  return data ?? []
}

function paramsDe(d: DadosLancamento) {
  return {
    p_descricao: d.descricao,
    p_valor: d.valor,
    p_data_competencia: d.data_competencia,
    p_data_vencimento: d.data_vencimento,
    p_data_efetivacao: d.data_efetivacao,
    p_conta_id: d.conta_id,
    p_conta_destino_id: d.conta_destino_id,
    p_categoria_id: d.categoria_id,
    p_observacao: d.observacao,
    p_negocio_id: d.negocio_id,
    p_pessoa_id: d.pessoa_id,
  }
}

function useInvalidarFinanceiro() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => {
    void qc.invalidateQueries({ queryKey: chaveLancamentos(organizacao.id) })
    void qc.invalidateQueries({ queryKey: ['contas', organizacao.id] })
    void qc.invalidateQueries({ queryKey: ['dashboard', organizacao.id] })
  }
}

export function useCriarLancamento() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async (d: DadosLancamento) => {
      const { data, error } = await supabase.rpc('criar_lancamento', { p_tipo: d.tipo, ...paramsDe(d) })
      if (error) throw error
      return data as Lancamento
    },
    onSuccess: invalidar,
  })
}

export function useAtualizarLancamento() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async ({ id, ...d }: DadosLancamento & { id: string }) => {
      const { data, error } = await supabase.rpc('atualizar_lancamento', { p_id: id, ...paramsDe(d) })
      if (error) throw error
      return data as Lancamento
    },
    onSuccess: invalidar,
  })
}

export function useEfetivarLancamento() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async ({ id, data_efetivacao }: { id: string; data_efetivacao: string }) => {
      const { data, error } = await supabase.rpc('efetivar_lancamento', { p_id: id, p_data_efetivacao: data_efetivacao })
      if (error) throw error
      return data as Lancamento
    },
    onSuccess: invalidar,
  })
}

export function useCancelarLancamento() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async ({ id, motivo }: { id: string; motivo: string }) => {
      const { data, error } = await supabase.rpc('cancelar_lancamento', { p_id: id, p_motivo: motivo || null })
      if (error) throw error
      return data as Lancamento
    },
    onSuccess: invalidar,
  })
}

export function useExcluirLancamento() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('excluir_lancamento', { p_id: id })
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}
