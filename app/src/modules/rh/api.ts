import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { DadosFerias, DadosFolha, DadosFuncionario, DadosPonto, Ferias, FolhaFuncionario, Funcionario, Ponto } from './tipos'

const chaveFuncionarios = (org: string) => ['funcionarios', org] as const
const chavePonto = (org: string) => ['funcionario_ponto', org] as const
const chaveFerias = (org: string) => ['funcionario_ferias', org] as const
const chaveFolha = (org: string) => ['funcionario_folha', org] as const

export function useFuncionarios() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chaveFuncionarios(organizacao.id),
    queryFn: async (): Promise<Funcionario[]> => {
      const { data, error } = await supabase.from('funcionarios').select('*').eq('organizacao_id', organizacao.id).order('ativo', { ascending: false }).order('criado_em', { ascending: false })
      if (error) throw error
      return (data ?? []).map((f) => ({ ...f, salario_base: Number(f.salario_base) }))
    },
  })
}

function useInvalidar(chave: (org: string) => readonly unknown[]) {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => qc.invalidateQueries({ queryKey: chave(organizacao.id) })
}

export function useCriarFuncionario() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidar(chaveFuncionarios)
  return useMutation({
    mutationFn: async (dados: DadosFuncionario) => {
      const { data, error } = await supabase.from('funcionarios').insert({ ...dados, organizacao_id: organizacao.id }).select().single()
      if (error) throw error
      return data as Funcionario
    },
    onSuccess: invalidar,
  })
}

export function useAtualizarFuncionario() {
  const invalidar = useInvalidar(chaveFuncionarios)
  return useMutation({
    mutationFn: async ({ id, ...dados }: DadosFuncionario & { id: string }) => {
      const { data, error } = await supabase.from('funcionarios').update(dados).eq('id', id).select().single()
      if (error) throw error
      return data as Funcionario
    },
    onSuccess: invalidar,
  })
}

export function usePonto(funcionarioId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chavePonto(organizacao.id), funcionarioId],
    enabled: funcionarioId !== null,
    queryFn: async (): Promise<Ponto[]> => {
      const { data, error } = await supabase.from('funcionario_ponto').select('*').eq('funcionario_id', funcionarioId as string).order('data', { ascending: false })
      if (error) throw error
      return data ?? []
    },
  })
}

export function useRegistrarPonto() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (dados: DadosPonto) => {
      const { data, error } = await supabase.from('funcionario_ponto').upsert(dados, { onConflict: 'funcionario_id,data' }).select().single()
      if (error) throw error
      return data as Ponto
    },
    onSuccess: (_d, vars) => qc.invalidateQueries({ queryKey: [...chavePonto(organizacao.id), vars.funcionario_id] }),
  })
}

export function useFerias(funcionarioId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveFerias(organizacao.id), funcionarioId],
    enabled: funcionarioId !== null,
    queryFn: async (): Promise<Ferias[]> => {
      const { data, error } = await supabase.from('funcionario_ferias').select('*').eq('funcionario_id', funcionarioId as string).order('periodo_aquisitivo_inicio', { ascending: false })
      if (error) throw error
      return data ?? []
    },
  })
}

export function useCriarFerias() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (dados: DadosFerias) => {
      const { data, error } = await supabase.from('funcionario_ferias').insert(dados).select().single()
      if (error) throw error
      return data as Ferias
    },
    onSuccess: (_d, vars) => qc.invalidateQueries({ queryKey: [...chaveFerias(organizacao.id), vars.funcionario_id] }),
  })
}

export function useAtualizarFerias() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, status }: { id: string; funcionario_id: string; status: Ferias['status'] }) => {
      const { data, error } = await supabase.from('funcionario_ferias').update({ status }).eq('id', id).select().single()
      if (error) throw error
      return data as Ferias
    },
    onSuccess: (_d, vars) => qc.invalidateQueries({ queryKey: [...chaveFerias(organizacao.id), vars.funcionario_id] }),
  })
}

/** Ponto de todos os funcionários da organização — RLS já restringe ao vínculo com funcionarios. */
export function usePontoGeral() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chavePonto(organizacao.id), 'geral'],
    queryFn: async (): Promise<Ponto[]> => {
      const { data, error } = await supabase.from('funcionario_ponto').select('*').order('data', { ascending: false }).limit(500)
      if (error) throw error
      return data ?? []
    },
  })
}

/** Férias de todos os funcionários da organização — RLS já restringe ao vínculo com funcionarios. */
export function useFeriasGeral() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveFerias(organizacao.id), 'geral'],
    queryFn: async (): Promise<Ferias[]> => {
      const { data, error } = await supabase.from('funcionario_ferias').select('*').order('periodo_aquisitivo_inicio', { ascending: false })
      if (error) throw error
      return data ?? []
    },
  })
}

export function useFolha(funcionarioId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveFolha(organizacao.id), funcionarioId],
    enabled: funcionarioId !== null,
    queryFn: async (): Promise<FolhaFuncionario[]> => {
      const { data, error } = await supabase.from('funcionario_folha').select('*').eq('funcionario_id', funcionarioId as string).order('mes', { ascending: false })
      if (error) throw error
      return (data ?? []).map((f) => ({ ...f, valor: Number(f.valor) }))
    },
  })
}

export function useLancarFolha() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (d: DadosFolha) => {
      const { data, error } = await supabase.rpc('lancar_folha_funcionario', {
        p_funcionario_id: d.funcionario_id, p_mes: d.mes, p_valor: d.valor, p_conta_id: d.conta_id,
        p_vencimento: d.vencimento, p_centro_custo_id: d.centro_custo_id, p_observacao: d.observacao,
      })
      if (error) throw error
      return data as FolhaFuncionario
    },
    onSuccess: (_d, vars) => qc.invalidateQueries({ queryKey: [...chaveFolha(organizacao.id), vars.funcionario_id] }),
  })
}
