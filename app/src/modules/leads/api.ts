import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { DadosLead, Lead, LeadEvento, StatusLead, TipoInteracaoLead } from './tipos'

const chaveLeads = (org: string) => ['leads', org] as const
const chaveEventos = (leadId: string) => ['lead_eventos', leadId] as const

export function useLeads() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chaveLeads(organizacao.id),
    queryFn: async (): Promise<Lead[]> => {
      const { data, error } = await supabase.from('leads').select('*').eq('organizacao_id', organizacao.id).order('criado_em', { ascending: false })
      if (error) throw error
      return data ?? []
    },
  })
}

function useInvalidarLeads() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => qc.invalidateQueries({ queryKey: chaveLeads(organizacao.id) })
}

export function useCriarLead() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidarLeads()
  return useMutation({
    mutationFn: async (dados: DadosLead) => {
      const { data, error } = await supabase.from('leads').insert({ ...dados, organizacao_id: organizacao.id }).select().single()
      if (error) throw error
      return data as Lead
    },
    onSuccess: invalidar,
  })
}

export function useAtualizarLead() {
  const invalidar = useInvalidarLeads()
  return useMutation({
    mutationFn: async ({ id, ...dados }: Partial<DadosLead> & { id: string }) => {
      const { data, error } = await supabase.from('leads').update(dados).eq('id', id).select().single()
      if (error) throw error
      return data as Lead
    },
    onSuccess: invalidar,
  })
}

export function useMoverLead() {
  const invalidar = useInvalidarLeads()
  return useMutation({
    mutationFn: async ({ id, status }: { id: string; status: StatusLead }) => {
      const { data, error } = await supabase.from('leads').update({ status }).eq('id', id).select().single()
      if (error) throw error
      return data as Lead
    },
    onSuccess: invalidar,
  })
}

export function useConverterLead() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  const invalidar = useInvalidarLeads()
  return useMutation({
    mutationFn: async (leadId: string) => {
      const { data, error } = await supabase.rpc('converter_lead_pessoa', { p_lead_id: leadId })
      if (error) throw error
      return data as { id: string; nome: string }
    },
    onSuccess: () => {
      invalidar()
      void qc.invalidateQueries({ queryKey: ['pessoas', organizacao.id] })
      void qc.invalidateQueries({ queryKey: ['vinculos', organizacao.id] })
    },
  })
}

export function useLeadEventos(leadId: string | null) {
  return useQuery({
    queryKey: chaveEventos(leadId ?? ''),
    enabled: leadId !== null,
    queryFn: async (): Promise<LeadEvento[]> => {
      const { data, error } = await supabase.from('lead_eventos').select('*').eq('lead_id', leadId as string).order('criado_em', { ascending: false })
      if (error) throw error
      return data ?? []
    },
  })
}

export function useRegistrarInteracao() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ lead_id, tipo, descricao }: { lead_id: string; tipo: TipoInteracaoLead; descricao: string | null }) => {
      const { data: auth } = await supabase.auth.getUser()
      const { data, error } = await supabase.from('lead_eventos').insert({ lead_id, tipo, descricao, usuario_id: auth.user?.id ?? null }).select().single()
      if (error) throw error
      return data as LeadEvento
    },
    onSuccess: (_d, vars) => qc.invalidateQueries({ queryKey: chaveEventos(vars.lead_id) }),
  })
}
