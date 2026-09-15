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

/** Sábado/domingo antecipa para a sexta anterior (mesma regra do banco, ajustar_dia_util). Sem feriados: não há fonte gratuita confiável. */
export function ajustarDiaUtil(dataISO: string): string {
  const d = new Date(`${dataISO}T00:00:00Z`)
  const dow = d.getUTCDay() // 0=domingo, 6=sábado
  if (dow === 0) d.setUTCDate(d.getUTCDate() - 2)
  else if (dow === 6) d.setUTCDate(d.getUTCDate() - 1)
  return d.toISOString().slice(0, 10)
}

/** Vencimento (calendário puro) da fatura em que uma compra na data informada entra — mesma chave de
 *  casamento que o banco usa para agrupar parcelas (fechar_fatura_cartao). NÃO ajusta fim de semana
 *  aqui: parcelas futuras são pré-geradas por projetar_lancamento somando "+1 mês" no calendário puro
 *  (recorrência genérica, sem noção de fim de semana) — se a data gravada em cada parcela já viesse
 *  ajustada, uma parcela futura caindo num domingo nunca bateria com o vencimento real da fatura (que
 *  aí sim é ajustado) e ficaria presa como "previsto" para sempre. O ajuste de dia útil vale só para a
 *  data de vencimento DA FATURA em si (ver vencimentoFaturaReal) — o que o dono vê e paga. */
export function vencimentoFatura(dataISO: string, cfg: CartaoConfig): string {
  const [ano, mes, dia] = dataISO.split('-').map(Number)
  let fAno = ano
  let fMes = mes
  if (dia > cfg.dia_fechamento) { fMes++; if (fMes > 12) { fMes = 1; fAno++ } }
  if (cfg.dia_vencimento <= cfg.dia_fechamento) { fMes++; if (fMes > 12) { fMes = 1; fAno++ } }
  return `${fAno}-${String(fMes).padStart(2, '0')}-${String(cfg.dia_vencimento).padStart(2, '0')}`
}

/** Vencimento REAL (ajustado a dia útil) da fatura — o que a fatura de verdade mostra e cobra. Só para exibição. */
export function vencimentoFaturaReal(dataISO: string, cfg: CartaoConfig): string {
  return ajustarDiaUtil(vencimentoFatura(dataISO, cfg))
}

export interface CartaoLimite {
  config_id: string
  conta_id: string
  limite_total: number
  uso_efetivado: number
  comprometido: number
  disponivel: number
}
