import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { DadosPessoa, PapelVinculo, Pessoa, Vinculo } from './tipos'

const chavePessoas = (org: string) => ['pessoas', org] as const
const chaveVinculos = (org: string) => ['vinculos', org] as const

export function usePessoas() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chavePessoas(organizacao.id),
    queryFn: async (): Promise<Pessoa[]> => {
      const { data, error } = await supabase.from('pessoas').select('*').eq('organizacao_id', organizacao.id).order('ativo', { ascending: false }).order('nome')
      if (error) throw error
      return data ?? []
    },
  })
}

export function useVinculos() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chaveVinculos(organizacao.id),
    queryFn: async (): Promise<Vinculo[]> => {
      const { data, error } = await supabase.from('pessoa_negocio_vinculos').select('*').eq('organizacao_id', organizacao.id).order('desde')
      if (error) throw error
      return data ?? []
    },
  })
}

function useInvalidarPessoas() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => {
    void qc.invalidateQueries({ queryKey: chavePessoas(organizacao.id) })
    void qc.invalidateQueries({ queryKey: chaveVinculos(organizacao.id) })
  }
}

export function useCriarPessoa() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidarPessoas()
  return useMutation({
    mutationFn: async (dados: DadosPessoa) => {
      const { data, error } = await supabase.from('pessoas').insert({ ...dados, organizacao_id: organizacao.id }).select().single()
      if (error) throw error
      return data as Pessoa
    },
    onSuccess: invalidar,
  })
}

export function useAtualizarPessoa() {
  const invalidar = useInvalidarPessoas()
  return useMutation({
    mutationFn: async ({ id, ...dados }: DadosPessoa & { id: string }) => {
      const { data, error } = await supabase.from('pessoas').update(dados).eq('id', id).select().single()
      if (error) throw error
      return data as Pessoa
    },
    onSuccess: invalidar,
  })
}

export function useCriarVinculo() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidarPessoas()
  return useMutation({
    mutationFn: async (v: { pessoa_id: string; negocio_id: string; papel: PapelVinculo }) => {
      const { data, error } = await supabase.from('pessoa_negocio_vinculos').insert({ ...v, organizacao_id: organizacao.id }).select().single()
      if (error) throw error
      return data as Vinculo
    },
    onSuccess: invalidar,
  })
}

export function useAtualizarVinculo() {
  const invalidar = useInvalidarPessoas()
  return useMutation({
    mutationFn: async ({ id, ativo }: { id: string; ativo: boolean }) => {
      const { data, error } = await supabase.from('pessoa_negocio_vinculos').update({ ativo }).eq('id', id).select().single()
      if (error) throw error
      return data as Vinculo
    },
    onSuccess: invalidar,
  })
}
