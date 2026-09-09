import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { Disparo, DisparoItem, DisparoModelo } from './tipos'

const chave = (org: string) => ['disparos', org] as const

export function useModelosDisparo() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'modelos'],
    queryFn: async (): Promise<DisparoModelo[]> => {
      const { data, error } = await supabase.from('disparo_modelos').select('*').eq('organizacao_id', organizacao.id).order('nome')
      if (error) throw error
      return (data ?? []) as DisparoModelo[]
    },
  })
}

export function useSalvarModeloDisparo() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (d: { id?: string; nome: string; texto: string }) => {
      const q = d.id
        ? supabase.from('disparo_modelos').update({ nome: d.nome, texto: d.texto }).eq('id', d.id)
        : supabase.from('disparo_modelos').insert({ nome: d.nome, texto: d.texto, organizacao_id: organizacao.id })
      const { data, error } = await q.select().single()
      if (error) throw error
      return data as DisparoModelo
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: chave(organizacao.id) }),
  })
}

export function useDisparos() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'lista'],
    queryFn: async (): Promise<Disparo[]> => {
      const { data, error } = await supabase.from('disparos').select('*, disparo_itens(status, pessoa_id, vencimento)').eq('organizacao_id', organizacao.id).order('criado_em', { ascending: false }).limit(50)
      if (error) throw error
      return (data ?? []) as Disparo[]
    },
  })
}

export function useItensDisparo(disparoId: string | null, aoVivo = false) {
  return useQuery({
    queryKey: ['disparos', 'itens', disparoId],
    enabled: Boolean(disparoId),
    refetchInterval: aoVivo ? 5000 : false,
    queryFn: async (): Promise<DisparoItem[]> => {
      const { data, error } = await supabase.from('disparo_itens').select('*').eq('disparo_id', disparoId!).order('criado_em')
      if (error) throw error
      return (data ?? []) as DisparoItem[]
    },
  })
}

export function useCriarDisparo() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (d: { negocio_id: string; modelo_nome: string; itens: { pessoa_id: string; mensagem: string }[] }) => {
      const { data, error } = await supabase.rpc('criar_disparo', { p_negocio_id: d.negocio_id, p_modelo_nome: d.modelo_nome, p_itens: d.itens })
      if (error) throw error
      return data as Disparo
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: chave(organizacao.id) }),
  })
}

/** Aciona a Edge Function (fila anda 3 itens por chamada, 15 s entre mensagens). */
export function useProcessarDisparos() {
  return useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc('processar_disparos')
      if (error) throw error
    },
  })
}

export function useReenviarFalhas() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (disparoId: string) => {
      const { data, error } = await supabase.rpc('reenviar_falhas_disparo', { p_disparo_id: disparoId })
      if (error) throw error
      return data as number
    },
    onSuccess: (_n, disparoId) => {
      void qc.invalidateQueries({ queryKey: chave(organizacao.id) })
      void qc.invalidateQueries({ queryKey: ['disparos', 'itens', disparoId] })
    },
  })
}
