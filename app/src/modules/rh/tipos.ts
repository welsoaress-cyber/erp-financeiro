export interface Funcionario {
  id: string
  organizacao_id: string
  negocio_id: string
  pessoa_id: string
  cargo: string | null
  departamento: string | null
  salario_base: number
  data_admissao: string
  data_demissao: string | null
  ativo: boolean
  criado_em: string
  atualizado_em: string
}

export interface DadosFuncionario {
  negocio_id: string
  pessoa_id: string
  cargo: string | null
  departamento: string | null
  salario_base: number
  data_admissao: string
  data_demissao: string | null
  ativo: boolean
}

export interface Ponto {
  id: string
  funcionario_id: string
  data: string
  entrada: string | null
  saida_almoco: string | null
  volta_almoco: string | null
  saida: string | null
  observacao: string | null
  criado_em: string
  atualizado_em: string
}

export interface DadosPonto {
  funcionario_id: string
  data: string
  entrada: string | null
  saida_almoco: string | null
  volta_almoco: string | null
  saida: string | null
  observacao: string | null
}

export const STATUS_FERIAS = ['programada', 'em_gozo', 'concluida', 'cancelada'] as const
export type StatusFerias = (typeof STATUS_FERIAS)[number]
export const ROTULO_STATUS_FERIAS: Record<StatusFerias, string> = {
  programada: 'Programada',
  em_gozo: 'Em gozo',
  concluida: 'Concluída',
  cancelada: 'Cancelada',
}

export interface Ferias {
  id: string
  funcionario_id: string
  periodo_aquisitivo_inicio: string
  periodo_aquisitivo_fim: string
  data_inicio: string | null
  data_fim: string | null
  status: StatusFerias
  observacao: string | null
  criado_em: string
  atualizado_em: string
}

export interface DadosFerias {
  funcionario_id: string
  periodo_aquisitivo_inicio: string
  periodo_aquisitivo_fim: string
  data_inicio: string | null
  data_fim: string | null
  status: StatusFerias
  observacao: string | null
}

export interface FolhaFuncionario {
  id: string
  organizacao_id: string
  funcionario_id: string
  mes: string
  valor: number
  lancamento_id: string
  observacao: string | null
  criado_em: string
}

export interface DadosFolha {
  funcionario_id: string
  mes: string
  valor: number
  conta_id: string
  vencimento: string
  centro_custo_id: string | null
  observacao: string | null
}

/** Horas trabalhadas no dia, calculadas no front a partir dos 4 horários (sem banco de horas). */
export function horasTrabalhadas(p: Pick<Ponto, 'entrada' | 'saida_almoco' | 'volta_almoco' | 'saida'>): number | null {
  if (!p.entrada || !p.saida) return null
  const min = (t: string) => { const [h, m] = t.split(':').map(Number); return h * 60 + m }
  let total = min(p.saida) - min(p.entrada)
  if (p.saida_almoco && p.volta_almoco) total -= min(p.volta_almoco) - min(p.saida_almoco)
  return total > 0 ? Math.round((total / 60) * 100) / 100 : null
}
