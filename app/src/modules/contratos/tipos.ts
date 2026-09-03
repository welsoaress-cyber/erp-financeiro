export const PERIODICIDADES = [
  { valor: 'mensal', rotulo: 'Mensal' },
  { valor: 'anual', rotulo: 'Anual' },
  { valor: 'unico', rotulo: 'Pagamento único' },
] as const
export type Periodicidade = (typeof PERIODICIDADES)[number]['valor']
export const ROTULO_PERIODICIDADE: Record<Periodicidade, string> = { mensal: 'Mensal', anual: 'Anual', unico: 'Único' }

export type TipoFinanceiroContrato = 'receita' | 'despesa'
export const ROTULO_TIPO_FINANCEIRO: Record<TipoFinanceiroContrato, string> = { receita: 'Cliente (receita)', despesa: 'Fornecedor (despesa)' }
export const ROTULO_PESSOA_CONTRATO: Record<TipoFinanceiroContrato, string> = { receita: 'cliente', despesa: 'fornecedor' }

export type StatusContrato = 'ativo' | 'suspenso' | 'encerrado'
export const ROTULO_STATUS_CONTRATO: Record<StatusContrato, string> = { ativo: 'Ativo', suspenso: 'Suspenso', encerrado: 'Encerrado' }

export interface Plano {
  id: string
  organizacao_id: string
  negocio_id: string
  nome: string
  descricao: string | null
  valor_tabela: number
  periodicidade: Periodicidade
  ativo: boolean
}

export interface DadosPlano {
  nome: string
  descricao: string | null
  valor_tabela: number
  periodicidade: Periodicidade
  ativo: boolean
}

export interface Contrato {
  id: string
  organizacao_id: string
  negocio_id: string
  pessoa_id: string
  plano_id: string
  codigo: number
  valor: number
  periodicidade: Periodicidade
  data_inicio: string
  data_fim: string | null
  dia_vencimento: number
  status: StatusContrato
  observacao: string | null
  faturamento_automatico: boolean
  faturar_desde: string | null
  conta_id: string | null
  tipo_financeiro: TipoFinanceiroContrato
}

export interface DadosNovoContrato {
  negocio_id: string
  pessoa_id: string
  plano_id: string
  valor: number
  periodicidade: Periodicidade
  data_inicio: string
  dia_vencimento: number
  observacao: string | null
  faturar_desde: string | null
  conta_id: string | null
  tipo_financeiro: TipoFinanceiroContrato
}

export interface ResultadoContrato {
  contrato_id: string
  receitas: number
  despesas: number
  resultado: number
  lancamentos: number
  primeiro_lancamento: string | null
  ultimo_lancamento: string | null
}

export interface ReceitaRecorrente {
  negocio_id: string
  negocio: string
  contratos_ativos: number
  contratos_suspensos: number
  mrr: number
}

export interface Faturamento {
  id: string
  contrato_id: string
  competencia: string
  lancamento_id: string
  gerado_em: string
  status_lancamento: 'previsto' | 'efetivado' | 'cancelado'
  valor: number
  data_vencimento: string
  data_efetivacao: string | null
  descricao: string
}

export interface ExecucaoFaturamento {
  id: number
  executado_em: string
  origem: 'manual' | 'agendado'
  ate: string
  gerados: number
  pendencias: Array<{ contrato_id: string; codigo: number; negocio_id: string; motivo: string }>
}

export const codigoContrato = (c: Pick<Contrato, 'codigo'>) => `#${String(c.codigo).padStart(3, '0')}`
