import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { AcessoPortal, DadosFaixa, DadosPortalConfig, DadosPremio, DadosPromocao, IndicacaoAdmin, IndicacaoFaixa, IndicacaoPremio, PortalConfig, PromocaoAdmin, SolicitacaoAdmin, StatusRede, StatusRedeAdmin } from './tipos'

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
export function useFaixasAdmin() {
  const { organizacao } = useOrganizacao()
  return useQuery({ queryKey: [...chave(organizacao.id), 'faixas'], queryFn: async (): Promise<IndicacaoFaixa[]> => { const { data, error } = await supabase.from('indicacao_faixas').select('*').eq('organizacao_id', organizacao.id).order('faixa'); if (error) throw error; return (data ?? []).map((f) => ({ ...f, plano_ate: f.plano_ate == null ? null : Number(f.plano_ate), teto: Number(f.teto) })) } })
}
export function useSalvarFaixa() {
  const { organizacao } = useOrganizacao(); const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (p: { id?: string; dados: DadosFaixa }) => {
      const q = p.id ? supabase.from('indicacao_faixas').update(p.dados).eq('id', p.id) : supabase.from('indicacao_faixas').insert({ ...p.dados, organizacao_id: organizacao.id })
      const { error } = await q.select().single(); if (error) throw error
    },
    onSuccess: invalidar,
  })
}
export function usePremiosAdmin() {
  const { organizacao } = useOrganizacao()
  return useQuery({ queryKey: [...chave(organizacao.id), 'premios'], queryFn: async (): Promise<IndicacaoPremio[]> => { const { data, error } = await supabase.from('indicacao_premios').select('*').eq('organizacao_id', organizacao.id).order('faixa').order('nome'); if (error) throw error; return data ?? [] } })
}
export function useSalvarPremio() {
  const { organizacao } = useOrganizacao(); const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (p: { id?: string; dados: DadosPremio }) => {
      const q = p.id ? supabase.from('indicacao_premios').update(p.dados).eq('id', p.id) : supabase.from('indicacao_premios').insert({ ...p.dados, organizacao_id: organizacao.id })
      const { error } = await q.select().single(); if (error) throw error
    },
    onSuccess: invalidar,
  })
}
/** Cadastro em lote: cada foto vira um prêmio; o item da categoria Brindes é criado junto (saldo 0 — dar entrada na compra). */
export function useCriarPremiosLote() {
  const { organizacao } = useOrganizacao(); const invalidar = useInvalidar(); const qc = useQueryClient()
  return useMutation({
    mutationFn: async (p: { negocioId: string; faixa: number; premios: { nome: string; foto: string }[] }) => {
      // categoria Brindes do negócio (cria se não existir)
      const { data: cats, error: eCat } = await supabase.from('estoque_categorias').select('id, nome').eq('negocio_id', p.negocioId)
      if (eCat) throw eCat
      let catId = (cats ?? []).find((c) => c.nome.toLowerCase().startsWith('brinde'))?.id as string | undefined
      if (!catId) {
        const { data: nova, error } = await supabase.from('estoque_categorias').insert({ organizacao_id: organizacao.id, negocio_id: p.negocioId, nome: 'Brindes' }).select('id').single()
        if (error) throw error
        catId = nova.id as string
      }
      let criados = 0
      for (const pr of p.premios) {
        const codigo = `BR-${Math.random().toString(36).slice(2, 8).toUpperCase()}`
        const { data: item, error: eItem } = await supabase.from('estoque_itens').insert({
          organizacao_id: organizacao.id, negocio_id: p.negocioId, categoria_id: catId, codigo,
          nome: pr.nome.slice(0, 80), unidade_medida: 'unidade',
        }).select('id').single()
        if (eItem) throw new Error(`"${pr.nome}": ${eItem.message} (${criados} prêmio(s) já criados)`)
        const { error: ePremio } = await supabase.from('indicacao_premios').insert({
          organizacao_id: organizacao.id, negocio_id: p.negocioId, nome: pr.nome.slice(0, 80), foto: pr.foto, faixa: p.faixa, item_id: item.id,
        })
        if (ePremio) throw new Error(`"${pr.nome}": ${ePremio.message} (${criados} prêmio(s) já criados)`)
        criados++
      }
      return criados
    },
    onSuccess: () => { invalidar(); void qc.invalidateQueries({ queryKey: ['estoque', organizacao.id] }) },
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
export function useCriarIndicacaoAdmin() {
  const invalidar = useInvalidar()
  return useMutation({ mutationFn: async (p: { negocioId: string; indicanteId: string; nome: string; telefone: string }) => { const { error } = await supabase.rpc('criar_indicacao_admin', { p_negocio_id: p.negocioId, p_indicador_pessoa_id: p.indicanteId, p_nome: p.nome, p_telefone: p.telefone }); if (error) throw error }, onSuccess: invalidar })
}
export function useEscolherPresenteAdmin() {
  const invalidar = useInvalidar()
  return useMutation({ mutationFn: async (p: { id: string; itemId: string }) => { const { error } = await supabase.rpc('escolher_presente_indicacao', { p_indicacao_id: p.id, p_item_id: p.itemId }); if (error) throw error }, onSuccess: invalidar })
}
export function useEntregarPresente() {
  const invalidar = useInvalidar()
  return useMutation({ mutationFn: async (p: { id: string; observacao?: string }) => { const { error } = await supabase.rpc('entregar_presente_indicacao', { p_indicacao_id: p.id, p_observacao: p.observacao ?? null }); if (error) throw error }, onSuccess: invalidar })
}
export function useAcessosPortal() {
  const { organizacao } = useOrganizacao()
  return useQuery({ queryKey: [...chave(organizacao.id), 'acessos'], queryFn: async (): Promise<AcessoPortal[]> => { const { data, error } = await supabase.from('vw_portal_acessos').select('*').eq('organizacao_id', organizacao.id).order('criado_em', { ascending: false }); if (error) throw error; return (data ?? []).map((a) => ({ ...a, indicacoes: Number(a.indicacoes) })) } })
}
export function useStatusRedeAdmin() {
  const { organizacao } = useOrganizacao()
  return useQuery({ queryKey: [...chave(organizacao.id), 'rede'], queryFn: async (): Promise<StatusRedeAdmin[]> => { const { data, error } = await supabase.from('portal_status_rede').select('*').eq('organizacao_id', organizacao.id); if (error) throw error; return data ?? [] } })
}
export function useSalvarStatusRede() {
  const { organizacao } = useOrganizacao(); const invalidar = useInvalidar()
  return useMutation({
    mutationFn: async (p: { id?: string; negocioId: string; status: StatusRede; titulo: string | null; descricao: string | null }) => {
      const dados = { status: p.status, titulo: p.titulo, descricao: p.descricao, atualizado_em: new Date().toISOString() }
      const q = p.id ? supabase.from('portal_status_rede').update(dados).eq('id', p.id) : supabase.from('portal_status_rede').insert({ ...dados, negocio_id: p.negocioId, organizacao_id: organizacao.id })
      const { error } = await q.select().single(); if (error) throw error
    },
    onSuccess: invalidar,
  })
}
export function useSolicitacoesAdmin() {
  const { organizacao } = useOrganizacao()
  return useQuery({ queryKey: [...chave(organizacao.id), 'solicitacoes'], queryFn: async (): Promise<SolicitacaoAdmin[]> => { const { data, error } = await supabase.from('vw_portal_solicitacoes').select('*').eq('organizacao_id', organizacao.id).order('criado_em', { ascending: false }).limit(300); if (error) throw error; return data ?? [] } })
}
export function useResponderSolicitacao() {
  const invalidar = useInvalidar()
  return useMutation({ mutationFn: async (p: { id: string; status: SolicitacaoAdmin['status']; resposta: string | null }) => { const { error } = await supabase.from('portal_solicitacoes').update({ status: p.status, resposta: p.resposta }).eq('id', p.id); if (error) throw error }, onSuccess: invalidar })
}
