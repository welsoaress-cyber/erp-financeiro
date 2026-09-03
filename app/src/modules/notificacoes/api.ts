import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { ConfigNotificacao, DadosConfigNotificacao, Notificacao, ResultadoExecucao } from './tipos'

const chave = (org: string) => ['notificacoes', org] as const

export function useConfigsNotificacao() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'config'],
    queryFn: async (): Promise<ConfigNotificacao[]> => {
      const { data, error } = await supabase.from('notificacoes_config').select('*').eq('organizacao_id', organizacao.id)
      if (error) throw error
      return data ?? []
    },
  })
}

export function useNotificacoes(negocioId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'log', negocioId],
    enabled: Boolean(negocioId),
    queryFn: async (): Promise<Notificacao[]> => {
      const { data, error } = await supabase.from('vw_notificacoes').select('*').eq('negocio_id', negocioId!).order('criado_em', { ascending: false }).limit(300)
      if (error) throw error
      return data ?? []
    },
  })
}

function useInvalidar() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => { void qc.invalidateQueries({ queryKey: chave(organizacao.id) }) }
}

export function useSalvarConfig() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (p: { id?: string; negocioId: string; dados: DadosConfigNotificacao }) => {
      const q = p.id
        ? supabase.from('notificacoes_config').update(p.dados).eq('id', p.id)
        : supabase.from('notificacoes_config').insert({ ...p.dados, negocio_id: p.negocioId, organizacao_id: organizacao.id })
      const { data, error } = await q.select().single()
      if (error) throw error
      return data as ConfigNotificacao
    },
    onSuccess: invalidar,
  })
}

export function useExecutarNotificacoes() {
  const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (data?: string) => {
      const { data: r, error } = await supabase.rpc('executar_notificacoes_agora', data ? { p_data: data } : {})
      if (error) throw error
      return r as ResultadoExecucao
    },
    onSuccess: invalidar,
  })
}

export function useEnviarTeste() {
  const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (p: { negocioId: string; pessoaId: string; tipo: string }) => {
      const { data, error } = await supabase.rpc('enviar_notificacao_teste', { p_negocio_id: p.negocioId, p_pessoa_id: p.pessoaId, p_tipo: p.tipo })
      if (error) throw error
      return data
    },
    onSuccess: invalidar,
  })
}

/** Dispara a Edge Function de envio agora (assíncrono; o histórico é reconsultado em seguida). */
export function useDispararEnvio() {
  const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('disparar_envio_notificacoes')
      if (error) throw error
      return data as number
    },
    onSuccess: () => { setTimeout(invalidar, 4000); setTimeout(invalidar, 12000) },
  })
}
