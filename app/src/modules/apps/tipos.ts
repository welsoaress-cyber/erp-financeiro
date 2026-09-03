import type { TipoSaldo } from '../negocios/tipos'

export interface ResumoCarteira {
  negocio_id: string
  organizacao_id: string
  negocio: string
  tipo_saldo: TipoSaldo
  taxa_conversao: number | null
  carteira_id: string | null
  conta_id: string | null
  categoria_consumo_id: string | null
  saldo: number
  total_recargas: number
  total_consumos: number
  apps_ativos: number
  anuidades_ativas: number
}

export interface AppCatalogo {
  id: string
  organizacao_id: string
  negocio_id: string
  plano_id: string
  nome: string
  custo: number
  ativo: boolean
}

export interface TransacaoCarteira {
  id: string
  negocio_id: string
  tipo: 'recarga' | 'consumo'
  valor: number
  valor_reais: number
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
  situacao: SituacaoContratoApp
  proximo_vencimento: string | null
}
export const ROTULO_SITUACAO: Record<SituacaoContratoApp, string> = { ativo: 'Ativo', vencido: 'Vencido', cancelado: 'Cancelado' }

/** Saldo em unidades da carteira: "R$ 87,00" ou "3,8 créditos". */
export function formatarSaldo(valor: number, tipo: TipoSaldo): string {
  if (tipo === 'dinheiro') return valor.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
  const n = valor.toLocaleString('pt-BR', { minimumFractionDigits: 0, maximumFractionDigits: 2 })
  return `${n} crédito${valor === 1 ? '' : 's'}`
}
