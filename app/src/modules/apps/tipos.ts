export type FormaPagamento = 'dinheiro' | 'credito'
export const FORMAS_PAGAMENTO = [
  { valor: 'dinheiro', rotulo: 'Dinheiro (R$)' },
  { valor: 'credito', rotulo: 'Créditos' },
] as const

export interface ResumoCarteira {
  negocio_id: string
  organizacao_id: string
  negocio: string
  carteira_id: string | null
  conta_id: string | null
  categoria_consumo_id: string | null
  saldo_dinheiro: number
  saldo_credito: number
  total_recargas_dinheiro: number
  total_recargas_credito: number
  total_consumos_dinheiro: number
  total_consumos_credito: number
  apps_ativos: number
  anuidades_ativas: number
}

export interface AppCatalogo {
  id: string
  organizacao_id: string
  negocio_id: string
  plano_id: string
  nome: string
  ativo: boolean
}

export interface TransacaoCarteira {
  id: string
  negocio_id: string
  tipo: 'recarga' | 'consumo'
  forma_pagamento: FormaPagamento
  valor: number
  valor_reais: number | null
  app_id: string | null
  contrato_id: string | null
  lancamento_id: string | null
  data: string
  observacao: string | null
  criado_em: string
}

export type SituacaoContratoApp = 'ativo' | 'vencido' | 'cancelado'
export interface ContratoApp {
  contrato_id: string
  negocio_id: string
  app_id: string
  app: string
  pessoa_id: string
  codigo: number
  anuidade: number
  data_inicio: string
  data_fim: string | null
  status: 'ativo' | 'suspenso' | 'encerrado'
  forma_pagamento: FormaPagamento | null
  valor_pago: number | null
  situacao: SituacaoContratoApp
  proximo_vencimento: string | null
}
export const ROTULO_SITUACAO: Record<SituacaoContratoApp, string> = { ativo: 'Ativo', vencido: 'Vencido', cancelado: 'Cancelado' }

/** Valor em unidades da forma de pagamento: "R$ 87,00" ou "3,8 créditos". */
export function formatarValor(valor: number, forma: FormaPagamento): string {
  if (forma === 'dinheiro') return valor.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
  const n = valor.toLocaleString('pt-BR', { minimumFractionDigits: 0, maximumFractionDigits: 2 })
  return `${n} crédito${valor === 1 ? '' : 's'}`
}
