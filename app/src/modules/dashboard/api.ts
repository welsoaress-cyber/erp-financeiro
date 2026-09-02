import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { Lancamento } from '../lancamentos/tipos'

export interface ResultadoMensal { mes: string; receitas: number; despesas: number; resultado: number }

export function useResultadoMensal(mes: string) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: ['dashboard', organizacao.id, 'resultado', mes],
    queryFn: async (): Promise<ResultadoMensal> => {
      const { data, error } = await supabase
        .from('vw_resultado_mensal')
        .select('mes, receitas, despesas, resultado')
        .eq('organizacao_id', organizacao.id)
        .eq('mes', mes)
        .maybeSingle()
      if (error) throw error
      return data ?? { mes, receitas: 0, despesas: 0, resultado: 0 }
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
