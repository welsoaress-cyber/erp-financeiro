import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { CompraTotais, DestinoCompra, Pedido, PedidoItem, Requisicao, RequisicaoItem } from './tipos'

const chave = (org: string) => ['compras', org] as const

function useInvalidar() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => { void qc.invalidateQueries({ queryKey: chave(organizacao.id) }) }
}

export function useRequisicoes() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'requisicoes'],
    queryFn: async (): Promise<Requisicao[]> => {
      const { data, error } = await supabase.from('compra_requisicoes').select('*').eq('organizacao_id', organizacao.id).order('numero', { ascending: false })
      if (error) throw error
      return (data ?? []) as Requisicao[]
    },
  })
}

export function useRequisicaoItens(reqId?: string | null) {
  return useQuery({
    queryKey: ['compras', 'req_itens', reqId ?? 'nenhum'],
    enabled: !!reqId,
    queryFn: async (): Promise<RequisicaoItem[]> => {
      const { data, error } = await supabase.from('compra_requisicao_itens').select('*').eq('requisicao_id', reqId!).order('ordem')
      if (error) throw error
      return (data ?? []).map((i) => ({ ...i, quantidade: Number(i.quantidade) })) as RequisicaoItem[]
    },
  })
}

export function usePedidos() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'pedidos'],
    queryFn: async (): Promise<Pedido[]> => {
      const { data, error } = await supabase.from('compras').select('*').eq('organizacao_id', organizacao.id).order('numero', { ascending: false })
      if (error) throw error
      return (data ?? []).map((p) => ({ ...p, valor_frete: Number(p.valor_frete), valor_desconto: Number(p.valor_desconto) })) as Pedido[]
    },
  })
}

export function usePedidoItens(pedidoId?: string | null) {
  return useQuery({
    queryKey: ['compras', 'ped_itens', pedidoId ?? 'nenhum'],
    enabled: !!pedidoId,
    queryFn: async (): Promise<PedidoItem[]> => {
      const { data, error } = await supabase.from('compra_itens').select('*').eq('compra_id', pedidoId!).order('id')
      if (error) throw error
      return (data ?? []).map((i) => ({ ...i, quantidade: Number(i.quantidade), valor_unitario: Number(i.valor_unitario), quantidade_recebida: Number(i.quantidade_recebida) })) as PedidoItem[]
    },
  })
}

export function useTotaisPedido(pedidoId?: string | null) {
  return useQuery({
    queryKey: ['compras', 'ped_totais', pedidoId ?? 'nenhum'],
    enabled: !!pedidoId,
    queryFn: async (): Promise<CompraTotais | null> => {
      const { data, error } = await supabase.from('vw_compras_totais').select('*').eq('compra_id', pedidoId!).maybeSingle()
      if (error) throw error
      if (!data) return null
      return { ...data, total_itens: Number(data.total_itens), total_recebido: Number(data.total_recebido), total_final: Number(data.total_final) } as CompraTotais
    },
  })
}

export function useCriarRequisicao() {
  const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (d: { negocio_id: string; itens: Array<{ descricao: string; quantidade: number; destino: DestinoCompra; item_id?: string | null; observacao?: string | null }>; justificativa?: string | null }) => {
      const { data, error } = await supabase.rpc('criar_requisicao_compra', { p_negocio_id: d.negocio_id, p_itens: d.itens, p_justificativa: d.justificativa ?? null })
      if (error) throw error
      return data as Requisicao
    },
    onSuccess: invalidar,
  })
}

export function useAprovarRequisicao() {
  const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (d: { id: string; fornecedor_id: string; valores: Array<{ valor_unitario: number; categoria_id?: string | null; contrato_id?: string | null }>; data_pedido?: string; previsao_entrega?: string | null; condicao_pagamento?: string | null; valor_frete?: number; valor_desconto?: number; observacao?: string | null }) => {
      const { data, error } = await supabase.rpc('aprovar_requisicao_compra', {
        p_id: d.id, p_fornecedor_id: d.fornecedor_id, p_valores: d.valores,
        p_data_pedido: d.data_pedido ?? undefined,
        p_previsao_entrega: d.previsao_entrega ?? null,
        p_condicao_pagamento: d.condicao_pagamento ?? null,
        p_valor_frete: d.valor_frete ?? 0, p_valor_desconto: d.valor_desconto ?? 0,
        p_observacao: d.observacao ?? null,
      })
      if (error) throw error
      return data as Pedido
    },
    onSuccess: invalidar,
  })
}

export function useRejeitarRequisicao() {
  const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (d: { id: string; motivo: string }) => {
      const { data, error } = await supabase.rpc('rejeitar_requisicao_compra', { p_id: d.id, p_motivo: d.motivo })
      if (error) throw error
      return data as Requisicao
    },
    onSuccess: invalidar,
  })
}

export function useCancelarRequisicao() {
  const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (id: string) => {
      const { data, error } = await supabase.rpc('cancelar_requisicao_compra', { p_id: id })
      if (error) throw error
      return data as Requisicao
    },
    onSuccess: invalidar,
  })
}

export function useCancelarPedido() {
  const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (d: { id: string; motivo?: string | null }) => {
      const { data, error } = await supabase.rpc('cancelar_pedido_compra', { p_id: d.id, p_motivo: d.motivo ?? null })
      if (error) throw error
      return data as Pedido
    },
    onSuccess: invalidar,
  })
}
