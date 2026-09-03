import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { AcessoPortal, DadosPortalConfig, DadosPromocao, IndicacaoAdmin, PortalConfig, PromocaoAdmin } from './tipos'

const chave = (org: string) => ['portal-admin', org] as const
function useInvalidar() { const { organizacao } = useOrganizacao(); const qc = useQueryClient(); return () => { void qc.invalidateQueries({ queryKey: chave(organizacao.id) }); void qc.invalidateQueries({ queryKey: ['contratos', organizacao.id] }) } }

export function usePortalConfigs() {
  const { organizacao } = useOrganizacao()
  return useQuery({ queryKey: [...chave(organizacao.id), 'config'], queryFn: async (): Promise<PortalConfig[]> => { const { data, error } = await supabase.from('portal_config').select('*').eq('organizacao_id', organizacao.id); if (error) throw error; return (data ?? []).map((c) => ({ ...c, beneficio_indicacao: Number(c.beneficio_indicacao) })) } })
}
export function useSalvarPortalConfig() {
  const { organizacao } = useOrganizacao(); const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (p: { id?: string; negocioId: string; dados: DadosPortalConfig }) => {
      const q = p.id ? supabase.from('portal_config').update(p.dados).eq('id', p.id) : supabase.from('portal_config').insert({ ...p.dados, negocio_id: p.negocioId, organizacao_id: organizacao.id })
      const { error } = await q.select().single(); if (error) throw error
    },
    onSuccess: invalidar,
  })
}
export function usePromocoesAdmin() {
  const { organizacao } = useOrganizacao()
  return useQuery({ queryKey: [...chave(organizacao.id), 'promocoes'], queryFn: async (): Promise<PromocaoAdmin[]> => { const { data, error } = await supabase.from('promocoes').select('*').eq('organizacao_id', organizacao.id).order('data_inicio', { ascending: false }); if (error) throw error; return data ?? [] } })
}
export function useSalvarPromocao() {
  const { organizacao } = useOrganizacao(); const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (p: { id?: string; dados: DadosPromocao }) => {
      const q = p.id ? supabase.from('promocoes').update(p.dados).eq('id', p.id) : supabase.from('promocoes').insert({ ...p.dados, organizacao_id: organizacao.id })
      const { error } = await q.select().single(); if (error) throw error
    },
    onSuccess: invalidar,
  })
}
export function useIndicacoesAdmin() {
  const { organizacao } = useOrganizacao()
  return useQuery({ queryKey: [...chave(organizacao.id), 'indicacoes'], queryFn: async (): Promise<IndicacaoAdmin[]> => { const { data, error } = await supabase.from('indicacoes').select('*').eq('organizacao_id', organizacao.id).order('criado_em', { ascending: false }).limit(300); if (error) throw error; return (data ?? []).map((i) => ({ ...i, beneficio_valor: Number(i.beneficio_valor) })) } })
}
export function useConverterIndicacao() {
  const invalidar = useInvalidar()
  return useMutation({ mutationFn: async (p: { id: string; pessoaId: string }) => { const { error } = await supabase.rpc('converter_indicacao', { p_indicacao_id: p.id, p_indicado_pessoa_id: p.pessoaId }); if (error) throw error }, onSuccess: invalidar })
}
export function useCancelarIndicacao() {
  const invalidar = useInvalidar()
  return useMutation({ mutationFn: async (p: { id: string; observacao: string | null }) => { const { error } = await supabase.from('indicacoes').update({ status: 'cancelada', observacao: p.observacao }).eq('id', p.id); if (error) throw error }, onSuccess: invalidar })
}
export function useAcessosPortal() {
  const { organizacao } = useOrganizacao()
  return useQuery({ queryKey: [...chave(organizacao.id), 'acessos'], queryFn: async (): Promise<AcessoPortal[]> => { const { data, error } = await supabase.from('vw_portal_acessos').select('*').eq('organizacao_id', organizacao.id).order('criado_em', { ascending: false }); if (error) throw error; return (data ?? []).map((a) => ({ ...a, indicacoes: Number(a.indicacoes) })) } })
}
