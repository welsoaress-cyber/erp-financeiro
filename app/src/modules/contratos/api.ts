import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { Contrato, DadosNovoContrato, DadosPlano, ExecucaoFaturamento, Faturamento, Plano, ReceitaRecorrente, ResultadoContrato, StatusContrato } from './tipos'

const chavePlanos = (org: string) => ['planos', org] as const
const chaveContratos = (org: string) => ['contratos', org] as const

export function usePlanos() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chavePlanos(organizacao.id),
    queryFn: async (): Promise<Plano[]> => {
      const { data, error } = await supabase.from('planos').select('*').eq('organizacao_id', organizacao.id).order('nome')
      if (error) throw error
      return (data ?? []).map((p) => ({ ...p, valor_tabela: Number(p.valor_tabela) }))
    },
  })
}

export function useContratos() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chaveContratos(organizacao.id),
    queryFn: async (): Promise<Contrato[]> => {
      const { data, error } = await supabase.from('contratos').select('*').eq('organizacao_id', organizacao.id).order('codigo', { ascending: false })
      if (error) throw error
      return (data ?? []).map((c) => ({ ...c, valor: Number(c.valor) }))
    },
  })
}

export function useResultadoContratos() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveContratos(organizacao.id), 'resultado'],
    queryFn: async (): Promise<ResultadoContrato[]> => {
      const { data, error } = await supabase.from('vw_resultado_por_contrato').select('contrato_id, receitas, despesas, resultado, lancamentos, primeiro_lancamento, ultimo_lancamento').eq('organizacao_id', organizacao.id)
      if (error) throw error
      return (data ?? []).map((r) => ({ ...r, receitas: Number(r.receitas), despesas: Number(r.despesas), resultado: Number(r.resultado), lancamentos: Number(r.lancamentos) }))
    },
  })
}

export function useReceitaRecorrente() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveContratos(organizacao.id), 'mrr'],
    queryFn: async (): Promise<ReceitaRecorrente[]> => {
      const { data, error } = await supabase.from('vw_receita_recorrente').select('negocio_id, negocio, contratos_ativos, contratos_suspensos, mrr').eq('organizacao_id', organizacao.id).order('negocio')
      if (error) throw error
      return (data ?? []).map((r) => ({ ...r, mrr: Number(r.mrr), contratos_ativos: Number(r.contratos_ativos), contratos_suspensos: Number(r.contratos_suspensos) }))
    },
  })
}

function useInvalidarContratos() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => {
    void qc.invalidateQueries({ queryKey: chavePlanos(organizacao.id) })
    void qc.invalidateQueries({ queryKey: chaveContratos(organizacao.id) })
    void qc.invalidateQueries({ queryKey: ['vinculos', organizacao.id] })
    void qc.invalidateQueries({ queryKey: ['lancamentos', organizacao.id] })
    void qc.invalidateQueries({ queryKey: ['dashboard', organizacao.id] })
  }
}

export function useFaturamentos() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveContratos(organizacao.id), 'faturamentos'],
    queryFn: async (): Promise<Faturamento[]> => {
      const { data, error } = await supabase.from('vw_faturamentos').select('*').eq('organizacao_id', organizacao.id).order('competencia', { ascending: false })
      if (error) throw error
      return (data ?? []).map((f) => ({ ...f, valor: Number(f.valor) }))
    },
  })
}

export function useUltimaExecucao() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveContratos(organizacao.id), 'execucao'],
    queryFn: async (): Promise<ExecucaoFaturamento | null> => {
      const { data, error } = await supabase.from('faturamento_execucoes').select('*').eq('organizacao_id', organizacao.id).order('executado_em', { ascending: false }).limit(1).maybeSingle()
      if (error) throw error
      return data as ExecucaoFaturamento | null
    },
  })
}

export function useGerarFaturamento() {
  const invalidar = useInvalidarContratos()
  return useMutation({
    mutationFn: async (ate?: string) => {
      const { data, error } = await supabase.rpc('gerar_faturamento_agora', ate ? { p_ate: ate } : {})
      if (error) throw error
      return ((data ?? []) as ExecucaoFaturamento[])[0] ?? null
    },
    onSuccess: invalidar,
  })
}

export function useCriarPlano() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidarContratos()
  return useMutation({
    mutationFn: async (d: DadosPlano & { negocio_id: string }) => {
      const { data, error } = await supabase.from('planos').insert({ ...d, organizacao_id: organizacao.id }).select().single()
      if (error) throw error
      return data as Plano
    },
    onSuccess: invalidar,
  })
}

export function useAtualizarPlano() {
  const invalidar = useInvalidarContratos()
  return useMutation({
    mutationFn: async ({ id, ...d }: DadosPlano & { id: string }) => {
      const { data, error } = await supabase.from('planos').update(d).eq('id', id).select().single()
      if (error) throw error
      return data as Plano
    },
    onSuccess: invalidar,
  })
}

export function useCriarContrato() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidarContratos()
  return useMutation({
    mutationFn: async (d: DadosNovoContrato) => {
      const { data, error } = await supabase.from('contratos').insert({ ...d, organizacao_id: organizacao.id }).select().single()
      if (error) throw error
      return data as Contrato
    },
    onSuccess: invalidar,
  })
}

export function useAtualizarContrato() {
  const invalidar = useInvalidarContratos()
  return useMutation({
    mutationFn: async ({ id, ...d }: { id: string; valor?: number; dia_vencimento?: number; observacao?: string | null; status?: StatusContrato; data_fim?: string | null; faturamento_automatico?: boolean; faturar_desde?: string | null; conta_id?: string | null }) => {
      const { data, error } = await supabase.from('contratos').update(d).eq('id', id).select().single()
      if (error) throw error
      return data as Contrato
    },
    onSuccess: invalidar,
  })
}
