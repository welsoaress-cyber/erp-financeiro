export interface BoletoPendente {
  id: string // lancamento_id
  organizacao_id: string
  negocio_id: string
  negocio: string
  contrato_id: string
  contrato_codigo: number
  dia_vencimento: number
  pessoa_id: string
  pessoa: string
  telefone: string | null
  descricao: string
  valor: number
  valor_desconto: number
  motivo_desconto: string | null
  codigo_barras: string | null
  data_vencimento: string
}
