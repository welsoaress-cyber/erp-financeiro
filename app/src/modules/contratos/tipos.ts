export const PERIODICIDADES = [
  { valor: 'mensal', rotulo: 'Mensal' },
  { valor: 'anual', rotulo: 'Anual' },
  { valor: 'unico', rotulo: 'Pagamento único' },
] as const
export type Periodicidade = (typeof PERIODICIDADES)[number]['valor']
export const ROTULO_PERIODICIDADE: Record<Periodicidade, string> = { mensal: 'Mensal', anual: 'Anual', unico: 'Único' }

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

export const codigoContrato = (c: Pick<Contrato, 'codigo'>) => `#${String(c.codigo).padStart(3, '0')}`
