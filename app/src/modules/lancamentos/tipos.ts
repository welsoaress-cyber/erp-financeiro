export const TIPOS_LANCAMENTO = [
  { valor: 'receita', rotulo: 'Receita' },
  { valor: 'despesa', rotulo: 'Despesa' },
  { valor: 'transferencia', rotulo: 'Transferência' },
] as const
export type TipoLancamento = (typeof TIPOS_LANCAMENTO)[number]['valor']

export type StatusLancamento = 'previsto' | 'efetivado' | 'cancelado'
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
  origem: 'manual' | 'sistema'
  negocio_id: string | null
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
}
