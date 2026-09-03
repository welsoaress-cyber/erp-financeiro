import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { Lancamento } from '../lancamentos/tipos'

export interface ResultadoNegocio { negocio_id: string | null; receitas: number; despesas: number; resultado: number }

/** Resultado do mês por negócio (negocio_id nulo = pessoal). */
export function useResultadoPorNegocio(mes: string) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: ['dashboard', organizacao.id, 'resultado-negocio', mes],
    queryFn: async (): Promise<ResultadoNegocio[]> => {
      const { data, error } = await supabase
        .from('vw_resultado_mensal_negocio')
        .select('negocio_id, receitas, despesas, resultado')
        .eq('organizacao_id', organizacao.id)
        .eq('mes', mes)
      if (error) throw error
      return (data ?? []).map((r) => ({ ...r, receitas: Number(r.receitas), despesas: Number(r.despesas), resultado: Number(r.resultado) }))
    },
  })
}

export function useUltimosLancamentos(limite = 8) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: ['dashboard', organizacao.id, 'ultimos', limite],
    queryFn: async (): Promise<Lancamento[]> => {
      const { data, error } = await supabase
        .from('lancamentos')
        .select('*')
        .eq('organizacao_id', organizacao.id)
        .eq('status', 'efetivado')
        .order('data_efetivacao', { ascending: false })
        .order('criado_em', { ascending: false })
        .limit(limite)
      if (error) throw error
      return data ?? []
    },
  })
}

export interface SaldoInicialNegocio { negocio_id: string | null; saldo: number }

/** Saldo consolidado (por negócio) já existente antes do mês selecionado começar. */
export function useSaldoInicial(mes: string) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: ['dashboard', organizacao.id, 'saldo-inicial', mes],
    queryFn: async (): Promise<SaldoInicialNegocio[]> => {
      const { data, error } = await supabase.rpc('saldo_inicial_mes', { p_mes: mes })
      if (error) throw error
      return (data ?? []).map((r: { negocio_id: string | null; saldo: number | string }) => ({ negocio_id: r.negocio_id, saldo: Number(r.saldo) }))
    },
  })
}
