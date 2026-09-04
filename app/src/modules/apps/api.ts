import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import { useInvalidarContratos } from '../contratos/api'
import type { AppCatalogo, ContratoApp, FormaPagamento, ResumoCarteira, TransacaoCarteira } from './tipos'

const chave = (org: string) => ['apps', org] as const

export function useResumosCarteira() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'resumo'],
    queryFn: async (): Promise<ResumoCarteira[]> => {
      const { data, error } = await supabase.from('vw_carteira_resumo').select('*').eq('organizacao_id', organizacao.id).order('negocio')
      if (error) throw error
      return (data ?? []).map((r) => ({
        ...r,
        saldo_dinheiro: Number(r.saldo_dinheiro),
        saldo_credito: Number(r.saldo_credito),
        total_recargas_dinheiro: Number(r.total_recargas_dinheiro),
        total_recargas_credito: Number(r.total_recargas_credito),
        total_consumos_dinheiro: Number(r.total_consumos_dinheiro),
        total_consumos_credito: Number(r.total_consumos_credito),
        apps_ativos: Number(r.apps_ativos),
        anuidades_ativas: Number(r.anuidades_ativas),
      }))
    },
  })
}

export function useAppsCatalogo() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'catalogo'],
    queryFn: async (): Promise<AppCatalogo[]> => {
      const { data, error } = await supabase.from('apps_catalogo').select('*').eq('organizacao_id', organizacao.id).order('nome')
      if (error) throw error
      return (data ?? []) as AppCatalogo[]
    },
  })
}

export function useTransacoesCarteira(negocioId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'transacoes', negocioId],
    enabled: Boolean(negocioId),
    queryFn: async (): Promise<TransacaoCarteira[]> => {
      const { data, error } = await supabase.from('transacoes_carteira').select('*').eq('negocio_id', negocioId!).order('data', { ascending: false }).order('criado_em', { ascending: false }).limit(200)
      if (error) throw error
      return (data ?? []).map((t) => ({ ...t, valor: Number(t.valor), valor_reais: t.valor_reais === null ? null : Number(t.valor_reais) }))
    },
  })
}

export function useContratosApp(negocioId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'contratos', negocioId],
    enabled: Boolean(negocioId),
    queryFn: async (): Promise<ContratoApp[]> => {
      const { data, error } = await supabase.from('vw_contratos_app').select('*').eq('negocio_id', negocioId!).order('codigo', { ascending: false })
      if (error) throw error
      return (data ?? []).map((c) => ({ ...c, anuidade: Number(c.anuidade), valor_pago: c.valor_pago === null ? null : Number(c.valor_pago) }))
    },
  })
}

function useInvalidarApps() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  const invalidarContratos = useInvalidarContratos()
  return () => {
    void qc.invalidateQueries({ queryKey: chave(organizacao.id) })
    void qc.invalidateQueries({ queryKey: ['contas', organizacao.id] })
    invalidarContratos()
  }
}

export function useConfigurarCarteira() {
  const invalidar = useInvalidarApps()
  return useMutation({
    mutationFn: async (p: { negocioId: string; contaId: string; categoriaConsumoId: string }) => {
      const { error } = await supabase.rpc('configurar_carteira', { p_negocio_id: p.negocioId, p_conta_id: p.contaId, p_categoria_consumo_id: p.categoriaConsumoId })
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}

export function useCriarApp() {
  const invalidar = useInvalidarApps()
  return useMutation({
    mutationFn: async (p: { negocioId: string; nome: string; anuidade: number }) => {
      const { data, error } = await supabase.rpc('criar_app', { p_negocio_id: p.negocioId, p_nome: p.nome, p_anuidade: p.anuidade })
      if (error) throw error
      return data as AppCatalogo
    },
    onSuccess: invalidar,
  })
}

export function useAtualizarApp() {
  const invalidar = useInvalidarApps()
  return useMutation({
    mutationFn: async (p: { id: string; nome: string; ativo: boolean }) => {
      const { data, error } = await supabase.from('apps_catalogo').update({ nome: p.nome, ativo: p.ativo }).eq('id', p.id).select().single()
      if (error) throw error
      return data as AppCatalogo
    },
    onSuccess: invalidar,
  })
}

export function useRecarregarCarteira() {
  const invalidar = useInvalidarApps()
  return useMutation({
    mutationFn: async (p: { negocioId: string; formaPagamento: FormaPagamento; valorReais: number; unidades: number | null; contaOrigemId: string; data: string; observacao: string | null }) => {
      const { data, error } = await supabase.rpc('recarregar_carteira', {
        p_negocio_id: p.negocioId, p_forma_pagamento: p.formaPagamento, p_valor_reais: p.valorReais, p_unidades: p.unidades,
        p_conta_origem_id: p.contaOrigemId, p_data: p.data, p_observacao: p.observacao,
      })
      if (error) throw error
      return data as TransacaoCarteira
    },
    onSuccess: invalidar,
  })
}

export function useAtivarApp() {
  const invalidar = useInvalidarApps()
  return useMutation({
    mutationFn: async (p: { negocioId: string; pessoaId: string; appId: string; formaPagamento: FormaPagamento; valor: number; data: string; anuidade: number | null; diaVencimento: number | null; observacao: string | null }) => {
      const { data, error } = await supabase.rpc('ativar_app', {
        p_negocio_id: p.negocioId, p_pessoa_id: p.pessoaId, p_app_id: p.appId, p_forma_pagamento: p.formaPagamento, p_valor: p.valor,
        p_data: p.data, p_anuidade: p.anuidade, p_dia_vencimento: p.diaVencimento, p_observacao: p.observacao,
      })
      if (error) throw error
      return data
    },
    onSuccess: invalidar,
  })
}
