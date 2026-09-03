export const TIPOS_LANCAMENTO = [
  { valor: 'receita', rotulo: 'Receita' },
  { valor: 'despesa', rotulo: 'Despesa' },
  { valor: 'transferencia', rotulo: 'Transferência' },
] as const
export type TipoLancamento = (typeof TIPOS_LANCAMENTO)[number]['valor']

export type StatusLancamento = 'previsto' | 'efetivado' | 'cancelado'

export const PERIODICIDADES_RECORRENCIA = [
  { valor: 'mensal', rotulo: 'Mensal' },
  { valor: 'quinzenal', rotulo: 'Quinzenal' },
  { valor: 'bimestral', rotulo: 'Bimestral' },
  { valor: 'trimestral', rotulo: 'Trimestral' },
  { valor: 'semestral', rotulo: 'Semestral' },
  { valor: 'anual', rotulo: 'Anual' },
] as const
export type PeriodicidadeRecorrencia = (typeof PERIODICIDADES_RECORRENCIA)[number]['valor']
export const ROTULO_PERIODICIDADE: Record<PeriodicidadeRecorrencia, string> = Object.fromEntries(PERIODICIDADES_RECORRENCIA.map((p) => [p.valor, p.rotulo])) as Record<PeriodicidadeRecorrencia, string>

export type TipoRecorrencia = 'fixa' | 'parcelada'
/** Fixa → "Fixo"; parcelada → "Parcela 2 de 12"; avulso → null. */
export function rotuloParcela(l: Pick<Lancamento, 'recorrente' | 'parcela_atual' | 'numero_parcelas'>): string | null {
  if (!l.recorrente || l.parcela_atual === null) return null
  return l.numero_parcelas ? `Parcela ${l.parcela_atual} de ${l.numero_parcelas}` : 'Fixo'
}
export const ROTULO_STATUS: Record<StatusLancamento, string> = { previsto: 'Previsto', efetivado: 'Efetivado', cancelado: 'Cancelado' }
export const ROTULO_TIPO: Record<TipoLancamento, string> = { receita: 'Receita', despesa: 'Despesa', transferencia: 'Transferência' }

export interface Lancamento {
  id: string
  organizacao_id: string
  tipo: TipoLancamento
  descricao: string
  valor: number
  data_competencia: string
  data_vencimento: string
  data_efetivacao: string | null
  status: StatusLancamento
  conta_id: string
  conta_destino_id: string | null
  categoria_id: string | null
  observacao: string | null
  origem: 'manual' | 'sistema' | 'faturamento'
  negocio_id: string | null
  pessoa_id: string | null
  contrato_id: string | null
  recorrente: boolean
  tipo_recorrencia: TipoRecorrencia | null
  periodicidade: PeriodicidadeRecorrencia | null
  numero_parcelas: number | null
  parcela_atual: number | null
  data_fim_recorrencia: string | null
  lancamento_origem_id: string | null
  cancelado_em: string | null
  motivo_cancelamento: string | null
  criado_em: string
  atualizado_em: string
}

/** Dados do formulário. `data_efetivacao` nula = previsto. */
export interface DadosLancamento {
  tipo: TipoLancamento
  descricao: string
  valor: number
  data_competencia: string
  data_vencimento: string
  data_efetivacao: string | null
  conta_id: string
  conta_destino_id: string | null
  categoria_id: string | null
  observacao: string | null
  negocio_id: string | null
  pessoa_id: string | null
  contrato_id: string | null
  recorrente: boolean
  periodicidade: PeriodicidadeRecorrencia | null
  numero_parcelas: number | null
  data_fim_recorrencia: string | null
}
