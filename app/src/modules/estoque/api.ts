import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { DadosItem, EstoqueCategoria, EstoqueItem, EstoqueMov } from './tipos'

const chave = (org: string) => ['estoque', org] as const

function useInvalidarEstoque() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => {
    void qc.invalidateQueries({ queryKey: chave(organizacao.id) })
    void qc.invalidateQueries({ queryKey: ['lancamentos', organizacao.id] })
  }
}

export function useEstoqueCategorias() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'categorias'],
    queryFn: async (): Promise<EstoqueCategoria[]> => {
      const { data, error } = await supabase.from('estoque_categorias').select('*').eq('organizacao_id', organizacao.id).order('nome')
      if (error) throw error
      return (data ?? []) as EstoqueCategoria[]
    },
  })
}

export function useSalvarEstoqueCategoria() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidarEstoque()
  return useMutation({
    mutationFn: async (d: { id?: string; negocio_id: string; nome: string; descricao?: string | null; ativo?: boolean }) => {
      const q = d.id
        ? supabase.from('estoque_categorias').update({ nome: d.nome, descricao: d.descricao ?? null, ativo: d.ativo ?? true }).eq('id', d.id)
        : supabase.from('estoque_categorias').insert({ negocio_id: d.negocio_id, nome: d.nome, descricao: d.descricao ?? null, organizacao_id: organizacao.id })
      const { data, error } = await q.select().single()
      if (error) throw error
      return data as EstoqueCategoria
    },
    onSuccess: invalidar,
  })
}

export function useEstoqueItens() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'itens'],
    queryFn: async (): Promise<EstoqueItem[]> => {
      const { data, error } = await supabase.from('estoque_itens').select('*').eq('organizacao_id', organizacao.id).order('nome')
      if (error) throw error
      return (data ?? []).map((i) => ({ ...i, valor_custo: Number(i.valor_custo), valor_venda: i.valor_venda == null ? null : Number(i.valor_venda), quantidade_atual: Number(i.quantidade_atual), quantidade_minima: Number(i.quantidade_minima), quantidade_maxima: i.quantidade_maxima == null ? null : Number(i.quantidade_maxima) })) as EstoqueItem[]
    },
  })
}

export function useSalvarEstoqueItem() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidarEstoque()
  return useMutation({
    mutationFn: async (d: DadosItem & { id?: string }) => {
      const { id, ...dados } = d
      const q = id
        ? supabase.from('estoque_itens').update(dados).eq('id', id)
        : supabase.from('estoque_itens').insert({ ...dados, organizacao_id: organizacao.id })
      const { data, error } = await q.select().single()
      if (error) throw error
      return data as EstoqueItem
    },
    onSuccess: invalidar,
  })
}

export function useEstoqueMovs(itemId?: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'movs', itemId ?? 'todas'],
    queryFn: async (): Promise<EstoqueMov[]> => {
      let q = supabase.from('estoque_movimentacoes').select('*').eq('organizacao_id', organizacao.id).order('criado_em', { ascending: false }).limit(200)
      if (itemId) q = q.eq('item_id', itemId)
      const { data, error } = await q
      if (error) throw error
      return (data ?? []).map((m) => ({ ...m, quantidade: Number(m.quantidade), valor_unitario: Number(m.valor_unitario), valor_total: Number(m.valor_total) })) as EstoqueMov[]
    },
  })
}

export function useEntradaEstoque() {
  const invalidar = useInvalidarEstoque()
  return useMutation({
    mutationFn: async (d: { item_id: string; quantidade: number; valor_total: number; data?: string; origem?: string; lancamento_id?: string | null; observacao?: string | null }) => {
      const { data, error } = await supabase.rpc('entrada_estoque', { p_item_id: d.item_id, p_quantidade: d.quantidade, p_valor_total: d.valor_total, p_data: d.data ?? undefined, p_origem: d.origem ?? 'compra', p_lancamento_id: d.lancamento_id ?? null, p_observacao: d.observacao ?? null })
      if (error) throw error
      return data as EstoqueMov
    },
    onSuccess: invalidar,
  })
}

export function useSaidaEstoque() {
  const invalidar = useInvalidarEstoque()
  return useMutation({
    mutationFn: async (d: { item_id: string; quantidade: number; origem: 'instalacao' | 'perda'; data?: string; pessoa_id?: string | null; contrato_id?: string | null; observacao?: string | null }) => {
      const { data, error } = await supabase.rpc('saida_estoque', { p_item_id: d.item_id, p_quantidade: d.quantidade, p_origem: d.origem, p_data: d.data ?? undefined, p_pessoa_id: d.pessoa_id ?? null, p_contrato_id: d.contrato_id ?? null, p_observacao: d.observacao ?? null })
      if (error) throw error
      return data as EstoqueMov
    },
    onSuccess: invalidar,
  })
}

export function useAjusteEstoque() {
  const invalidar = useInvalidarEstoque()
  return useMutation({
    mutationFn: async (d: { item_id: string; quantidade_nova: number; valor_total?: number | null; observacao?: string | null }) => {
      const { data, error } = await supabase.rpc('ajuste_estoque', { p_item_id: d.item_id, p_quantidade_nova: d.quantidade_nova, p_valor_total: d.valor_total ?? null, p_observacao: d.observacao ?? null })
      if (error) throw error
      return data as EstoqueMov
    },
    onSuccess: invalidar,
  })
}
