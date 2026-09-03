import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../core/supabase/client'
import { useAuth } from '../core/auth/useAuth'
import type { ContratoCliente, Fatura, Indicacao, Pagamento, PortalResumo, Promocao, ProximaFatura } from './tipos'

const chave = (u: string | undefined) => ['portal', u ?? ''] as const
const num = <T extends object>(rows: T[], campos: (keyof T)[]) => rows.map((r) => { const c = { ...r } as Record<keyof T, unknown>; for (const k of campos) c[k] = Number(c[k]); return c as T })

export function usePortalResumo() {
  const { usuario } = useAuth()
  return useQuery({
    queryKey: [...chave(usuario?.id), 'resumo'],
    enabled: Boolean(usuario),
    queryFn: async (): Promise<PortalResumo | null> => {
      const { data, error } = await supabase.rpc('portal_resumo')
      if (error) throw error
      if (!data) return null
      const r = data as PortalResumo
      return { ...r, em_aberto: Number(r.em_aberto), vencidas: Number(r.vencidas), contratos_ativos: Number(r.contratos_ativos), indicacoes_convertidas: Number(r.indicacoes_convertidas) }
    },
  })
}
function useLista<T extends object>(nome: string, fn: string, campos: (keyof T)[]) {
  const { usuario } = useAuth()
  return useQuery({
    queryKey: [...chave(usuario?.id), nome],
    enabled: Boolean(usuario),
    queryFn: async (): Promise<T[]> => { const { data, error } = await supabase.rpc(fn); if (error) throw error; return num((data ?? []) as T[], campos) },
  })
}
export const useFaturas = () => useLista<Fatura>('faturas', 'portal_faturas', ['valor'])
export const useProximasFaturas = () => useLista<ProximaFatura>('proximas', 'portal_proximas_faturas', ['valor'])
export const usePagamentos = () => useLista<Pagamento>('pagamentos', 'portal_pagamentos', ['valor'])
export const useContratosCliente = () => useLista<ContratoCliente>('contratos', 'portal_contratos', ['valor', 'descontos_pendentes'])
export const usePromocoesCliente = () => useLista<Promocao>('promocoes', 'portal_promocoes', [])
export const useIndicacoesCliente = () => useLista<Indicacao>('indicacoes', 'portal_indicacoes', ['beneficio_valor'])

function useInvalidarPortal() {
  const { usuario } = useAuth(); const qc = useQueryClient()
  return () => qc.invalidateQueries({ queryKey: chave(usuario?.id) })
}
export function useVincularPortal() {
  const invalidar = useInvalidarPortal()
  return useMutation({
    mutationFn: async (p: { documento: string; telefone: string }) => {
      const { data, error } = await supabase.rpc('portal_vincular', { p_documento: p.documento, p_telefone: p.telefone })
      if (error) throw error
      return data as { pessoa_id: string; codigo_indicacao: string; ja_vinculado: boolean }
    },
    onSuccess: invalidar,
  })
}
export function useIndicar() {
  const invalidar = useInvalidarPortal()
  return useMutation({
    mutationFn: async (p: { negocioId: string; nome: string; telefone: string }) => {
      const { error } = await supabase.rpc('portal_indicar', { p_negocio_id: p.negocioId, p_nome: p.nome, p_telefone: p.telefone })
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}
/** Página pública do link de indicação (sem login). */
export function useInfoIndicacao(codigo: string) {
  return useQuery({
    queryKey: ['portal-publico', codigo],
    queryFn: async (): Promise<{ negocio: string; texto: string | null; cor: string; logo: string | null; indicador: string } | null> => {
      const { data, error } = await supabase.rpc('portal_info_indicacao', { p_codigo: codigo })
      if (error) throw error
      return data ?? null
    },
  })
}
export function useIndicacaoPublica() {
  return useMutation({
    mutationFn: async (p: { codigo: string; nome: string; telefone: string }) => {
      const { data, error } = await supabase.rpc('portal_indicacao_publica', { p_codigo: p.codigo, p_nome: p.nome, p_telefone: p.telefone })
      if (error) throw error
      return data as { ok: boolean; negocio: string; repetida: boolean }
    },
  })
}
