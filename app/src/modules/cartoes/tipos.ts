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

/** Vencimento da fatura em que uma compra na data informada entra (mesma regra do fechamento no banco). */
export function vencimentoFatura(dataISO: string, cfg: CartaoConfig): string {
  const [ano, mes, dia] = dataISO.split('-').map(Number)
  let fAno = ano
  let fMes = mes
  if (dia > cfg.dia_fechamento) { fMes++; if (fMes > 12) { fMes = 1; fAno++ } }
  if (cfg.dia_vencimento <= cfg.dia_fechamento) { fMes++; if (fMes > 12) { fMes = 1; fAno++ } }
  return `${fAno}-${String(fMes).padStart(2, '0')}-${String(cfg.dia_vencimento).padStart(2, '0')}`
}
