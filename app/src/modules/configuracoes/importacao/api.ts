import { useMutation } from '@tanstack/react-query'
import { supabase } from '../../../core/supabase/client'
import { useInvalidarContratos } from '../../contratos/api'
import type { LinhaImportacao } from './csv'

export interface ItemRelatorio {
  linha: number
  status: 'importada' | 'rejeitada' | 'ignorada'
  motivo: string | null
  pessoa: 'nova' | 'existente' | null
  plano: 'novo' | 'existente' | null
  contrato: 'ativo' | 'encerrado' | 'existente' | null
}

export interface RelatorioImportacao {
  simulado: boolean
  negocio: string
  total: number
  importadas: number
  rejeitadas: number
  ignoradas: number
  pessoas_novas: number
  pessoas_existentes: number
  planos_novos: number
  contratos_ativos: number
  contratos_encerrados: number
  linhas: ItemRelatorio[]
}

export interface ParametrosImportacao {
  negocioId: string
  linhas: LinhaImportacao[]
  simular: boolean
  faturarDesde: string | null
}

export function useImportarClientes() {
  const invalidar = useInvalidarContratos()
  return useMutation({
    mutationFn: async (p: ParametrosImportacao): Promise<RelatorioImportacao> => {
      const { data, error } = await supabase.rpc('importar_clientes', {
        p_negocio_id: p.negocioId,
        p_linhas: p.linhas,
        p_simular: p.simular,
        p_faturar_desde: p.faturarDesde,
      })
      if (error) throw error
      return data as RelatorioImportacao
    },
    onSuccess: (_r, p) => { if (!p.simular) invalidar() },
  })
}
