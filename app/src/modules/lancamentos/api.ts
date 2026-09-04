import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import { fimDoMes } from '../../core/formatos'
import type { DadosLancamento, Lancamento } from './tipos'

export const chaveLancamentos = (organizacaoId: string) => ['lancamentos', organizacaoId] as const

/** Lançamentos do mês (por data de competência), mais recentes primeiro. */
export function useLancamentos(mes: string) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveLancamentos(organizacao.id), mes],
    queryFn: async (): Promise<Lancamento[]> => {
      const { data, error } = await supabase
        .from('lancamentos')
        .select('*')
        .eq('organizacao_id', organizacao.id)
        .gte('data_competencia', mes)
        .lte('data_competencia', fimDoMes(mes))
        .order('data_competencia', { ascending: false })
        .order('criado_em', { ascending: false })
      if (error) throw error
      return data ?? []
    },
  })
}

/** Projeção derivada dos contratos ativos: competências futuras ainda não faturadas, sempre com o valor atual do contrato. Nada é gravado. */
export interface ProjecaoContrato {
  contrato_id: string
  negocio_id: string | null
  pessoa_id: string | null
  conta_id: string | null
  categoria_id: string | null
  tipo: 'receita' | 'despesa'
  descricao: string
  valor: number
  data_competencia: string
  data_vencimento: string
}

export function useProjecaoContratos(mes: string) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveLancamentos(organizacao.id), 'projecao-contratos', mes],
    queryFn: async (): Promise<ProjecaoContrato[]> => {
      const { data, error } = await supabase.rpc('projecao_contratos', { p_organizacao: organizacao.id, p_de: mes, p_ate: fimDoMes(mes) })
      if (error) {
        if (error.code === 'PGRST202') return [] // migration 0031 ainda não aplicada
        throw error
      }
      return (data ?? []) as ProjecaoContrato[]
    },
  })
}

/** Existe algum lançamento gerado a partir deste (próxima parcela/ocorrência já projetada)? */
export function useTemProximaOcorrencia(id: string, habilitado: boolean) {
  return useQuery({
    queryKey: ['lancamentos', 'tem-proxima', id],
    enabled: habilitado,
    queryFn: async (): Promise<boolean> => {
      const { count, error } = await supabase
        .from('lancamentos')
        .select('id', { count: 'exact', head: true })
        .eq('lancamento_origem_id', id)
      if (error) throw error
      return (count ?? 0) > 0
    },
  })
}

/** Possíveis duplicados: mesma conta, mesmo valor, data ±1 dia, não cancelados. */
export async function buscarPossiveisDuplicados(organizacaoId: string, d: DadosLancamento, ignorarId?: string): Promise<Lancamento[]> {
  const base = new Date(`${d.data_competencia}T00:00:00Z`)
  const dia = (n: number) => new Date(base.getTime() + n * 86_400_000).toISOString().slice(0, 10)
  let q = supabase
    .from('lancamentos')
    .select('*')
    .eq('organizacao_id', organizacaoId)
    .eq('conta_id', d.conta_id)
    .eq('valor', d.valor)
    .neq('status', 'cancelado')
    .gte('data_competencia', dia(-1))
    .lte('data_competencia', dia(1))
  if (ignorarId) q = q.neq('id', ignorarId)
  const { data, error } = await q
  if (error) throw error
  return data ?? []
}

function paramsDe(d: DadosLancamento) {
  return {
    p_descricao: d.descricao,
    p_valor: d.valor,
    p_data_competencia: d.data_competencia,
    p_data_vencimento: d.data_vencimento,
    p_data_efetivacao: d.data_efetivacao,
    p_conta_id: d.conta_id,
    p_conta_destino_id: d.conta_destino_id,
    p_categoria_id: d.categoria_id,
    p_observacao: d.observacao,
    p_negocio_id: d.negocio_id,
    p_pessoa_id: d.pessoa_id,
    p_contrato_id: d.contrato_id,
    p_recorrente: d.recorrente,
    p_periodicidade: d.recorrente ? d.periodicidade : null,
    p_numero_parcelas: d.recorrente ? d.numero_parcelas : null,
    p_data_fim_recorrencia: d.recorrente ? d.data_fim_recorrencia : null,
  }
}

/** Próxima parcela já gerada a partir deste lançamento (bloqueia a edição da recorrência). */
export function useProximaParcela(lancamentoId: string | null, recorrente: boolean) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveLancamentos(organizacao.id), 'proxima', lancamentoId],
    enabled: Boolean(lancamentoId) && recorrente,
    queryFn: async (): Promise<Lancamento | null> => {
      const { data, error } = await supabase.from('lancamentos').select('*').eq('lancamento_origem_id', lancamentoId!).maybeSingle()
      if (error) throw error
      return (data as Lancamento | null) ?? null
    },
  })
}

function useInvalidarFinanceiro() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => {
    void qc.invalidateQueries({ queryKey: chaveLancamentos(organizacao.id) })
    void qc.invalidateQueries({ queryKey: ['contas', organizacao.id] })
    void qc.invalidateQueries({ queryKey: ['dashboard', organizacao.id] })
  }
}

/** Meses projetados automaticamente ao criar uma recorrência: teto máximo aceito por projetar_lancamento (5 anos).
 *  Para fixa, a cadeia continua se repondo sozinha a cada efetivação (gerar_proxima_parcela), então na prática nunca acaba. */
const MESES_PROJECAO_AUTOMATICA = 60

export function useCriarLancamento() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async (d: DadosLancamento) => {
      const { data, error } = await supabase.rpc('criar_lancamento', { p_tipo: d.tipo, ...paramsDe(d) })
      if (error) throw error
      const lancamento = data as Lancamento
      if (d.recorrente) {
        const { error: erroProjecao } = await supabase.rpc('projetar_lancamento', { p_id: lancamento.id, p_meses: MESES_PROJECAO_AUTOMATICA })
        if (erroProjecao) throw erroProjecao
      }
      return lancamento
    },
    onSuccess: invalidar,
  })
}

export function useAtualizarLancamento() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async ({ id, ...d }: DadosLancamento & { id: string }) => {
      const { data, error } = await supabase.rpc('atualizar_lancamento', { p_id: id, ...paramsDe(d) })
      if (error) throw error
      return data as Lancamento
    },
    onSuccess: invalidar,
  })
}

export function useEfetivarLancamento() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async ({ id, data_efetivacao }: { id: string; data_efetivacao: string }) => {
      const { data, error } = await supabase.rpc('efetivar_lancamento', { p_id: id, p_data_efetivacao: data_efetivacao })
      if (error) throw error
      return data as Lancamento
    },
    onSuccess: invalidar,
  })
}

export function useCancelarLancamento() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async ({ id, motivo }: { id: string; motivo: string }) => {
      const { data, error } = await supabase.rpc('cancelar_lancamento', { p_id: id, p_motivo: motivo || null })
      if (error) throw error
      return data as Lancamento
    },
    onSuccess: invalidar,
  })
}

export function useExcluirLancamento() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('excluir_lancamento', { p_id: id })
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}

/** Baixa parcial: efetiva o valor pago e cria um novo lançamento previsto com o restante. */
export function useBaixaParcial() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async ({ id, valor, data_efetivacao }: { id: string; valor: number; data_efetivacao: string }) => {
      const { data, error } = await supabase.rpc('baixar_parcial', { p_id: id, p_valor: valor, p_data_efetivacao: data_efetivacao })
      if (error) throw error
      return data as Lancamento
    },
    onSuccess: invalidar,
  })
}

/** Projeta N meses à frente de uma recorrência (fixa ou parcelada), sem exigir que a atual esteja paga. */
export function useProjetarLancamento() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async ({ id, meses }: { id: string; meses: number }) => {
      const { data, error } = await supabase.rpc('projetar_lancamento', { p_id: id, p_meses: meses })
      if (error) throw error
      return (data ?? []) as Lancamento[]
    },
    onSuccess: invalidar,
  })
}

export type EscopoEdicaoRecorrente = 'atual' | 'futuras' | 'todas'

/** Edita descrição/valor/observação em lote: só esta parcela, esta e as futuras, ou a cadeia inteira (inclusive já pagas). */
export function useAtualizarLancamentoRecorrente() {
  const invalidar = useInvalidarFinanceiro()
  return useMutation({
    mutationFn: async ({ id, descricao, valor, observacao, escopo }: { id: string; descricao: string; valor: number; observacao: string | null; escopo: EscopoEdicaoRecorrente }) => {
      const { data, error } = await supabase.rpc('atualizar_lancamento_recorrente', { p_id: id, p_descricao: descricao, p_valor: valor, p_observacao: observacao, p_escopo: escopo })
      if (error) throw error
      return (data ?? []) as Lancamento[]
    },
    onSuccess: invalidar,
  })
}

/** Lançamentos previstos com vencimento antes de uma data, independente do mês selecionado (pendências de meses anteriores). */
export function useLancamentosVencidosAntes(tipo: 'receita' | 'despesa', antesDe: string) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chaveLancamentos(organizacao.id), 'vencidos', tipo, antesDe],
    queryFn: async (): Promise<Lancamento[]> => {
      const { data, error } = await supabase
        .from('lancamentos')
        .select('*')
        .eq('organizacao_id', organizacao.id)
        .eq('tipo', tipo)
        .eq('status', 'previsto')
        .lt('data_vencimento', antesDe)
        .order('data_vencimento', { ascending: true })
      if (error) throw error
      return data ?? []
    },
  })
}
