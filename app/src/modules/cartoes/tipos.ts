export interface CartaoConfig {
  id: string
  organizacao_id: string
  conta_id: string
  dia_fechamento: number
  dia_vencimento: number
  limite_total: number
}

export type StatusFatura = 'aberta' | 'paga' | 'vencida'
export const ROTULO_STATUS_FATURA: Record<StatusFatura, string> = { aberta: 'Aberta', paga: 'Paga', vencida: 'Vencida' }

export interface Fatura {
  id: string
  conta_id: string
  periodo_inicio: string
  periodo_fim: string
  data_vencimento: string
  valor_total: number
  valor_pago: number
  status: StatusFatura
  data_pagamento: string | null
}
