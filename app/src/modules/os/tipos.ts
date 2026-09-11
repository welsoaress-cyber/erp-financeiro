export type TipoOs = 'instalacao' | 'manutencao' | 'reparo' | 'mudanca_endereco' | 'rompimento' | 'vistoria'
export type PrioridadeOs = 'normal' | 'urgente'
export type StatusOs = 'aberto' | 'em_atendimento' | 'pausado' | 'encerrado' | 'cancelado'
export type EventoOs = 'abertura' | 'atribuicao' | 'ciencia' | 'agendamento' | 'remarcacao_solicitada' | 'remarcacao_respondida' | 'inicio' | 'pausa' | 'retomada' | 'encerramento' | 'reabertura' | 'cancelamento' | 'avaliacao' | 'comissao'
export type DiagnosticoOs = 'conector' | 'cabo_rompido' | 'onu_queimada' | 'energia_cliente' | 'roteador_cliente' | 'sinal_degradado' | 'sem_defeito' | 'outro'
export type TipoMovTecnico = 'abastecimento' | 'consumo' | 'perda' | 'avaria' | 'devolucao'

export const ROTULO_TIPO_OS: Record<TipoOs, string> = {
  instalacao: 'Instalação', manutencao: 'Manutenção', reparo: 'Reparo', mudanca_endereco: 'Mudança de endereço', rompimento: 'Rompimento', vistoria: 'Vistoria',
}
export const ROTULO_STATUS_OS: Record<StatusOs, string> = {
  aberto: 'Aberto', em_atendimento: 'Em atendimento', pausado: 'Pausado', encerrado: 'Encerrado', cancelado: 'Cancelado',
}
export const ROTULO_EVENTO_OS: Record<EventoOs, string> = {
  abertura: 'Abertura', atribuicao: 'Atribuição', ciencia: 'Ciência', agendamento: 'Agendamento', remarcacao_solicitada: 'Remarcação solicitada',
  remarcacao_respondida: 'Remarcação respondida', inicio: 'Início', pausa: 'Pausa', retomada: 'Retomada', encerramento: 'Encerramento',
  reabertura: 'Reabertura', cancelamento: 'Cancelamento', avaliacao: 'Avaliação', comissao: 'Comissão',
}
export const ROTULO_DIAGNOSTICO: Record<DiagnosticoOs, string> = {
  conector: 'Conector sujo/quebrado', cabo_rompido: 'Cabo rompido', onu_queimada: 'ONU queimada', energia_cliente: 'Energia do cliente',
  roteador_cliente: 'Roteador do cliente', sinal_degradado: 'Sinal degradado', sem_defeito: 'Sem defeito encontrado', outro: 'Outro',
}
export const ROTULO_MOV_TECNICO: Record<TipoMovTecnico, string> = {
  abastecimento: 'Abastecimento', consumo: 'Consumo', perda: 'Perda', avaria: 'Avaria', devolucao: 'Devolução',
}

export interface Tecnico {
  id: string
  negocio_id: string
  pessoa_id: string
  usuario_id: string | null
  login: string | null
  nome: string
  telefone: string | null
  ativo: boolean
}

export interface TecnicoEstoque {
  id: string
  tecnico_id: string
  item_id: string
  quantidade: number
  quantidade_minima: number
}

export interface TecnicoMov {
  id: string
  tecnico_id: string
  item_id: string
  tipo: TipoMovTecnico
  quantidade: number
  valor_total: number
  motivo: string | null
  defeito_fabrica: boolean
  os_id: string | null
  criado_em: string
}

export interface BolsaResumo {
  tecnico_id: string
  negocio_id: string
  tecnico: string
  ativo: boolean
  itens_negativos: number
  itens_abaixo_minimo: number
  valor_em_campo: number
}

export interface OrdemServico {
  id: string
  negocio_id: string
  numero: string
  os_origem_id: string | null
  retorno: boolean
  contrato_id: string | null
  pessoa_id: string | null
  tecnico_id: string | null
  cto_id: string | null
  tipo: TipoOs
  prioridade: PrioridadeOs
  status: StatusOs
  aberto_via: 'admin' | 'portal' | 'interno'
  descricao: string
  data_agendada: string | null
  hora_agendada: string | null
  remarcacao_data: string | null
  remarcacao_hora: string | null
  remarcacao_motivo: string | null
  data_ciencia: string | null
  data_inicio: string | null
  data_fim: string | null
  pausado_em: string | null
  tempo_total_minutos: number | null
  tempo_pausa_minutos: number
  tempo_execucao_minutos: number | null
  diagnostico: DiagnosticoOs | null
  sinal_dbm: number | null
  avaliacao_resolvido: boolean | null
  avaliacao_nota: number | null
  comissao_lancamento_id: string | null
  observacao: string | null
  criado_em: string
}

export interface OsMaterial {
  id: string
  os_id: string
  item_id: string
  quantidade: number
  valor_unitario: number
  valor_total: number
}

export interface OsHistorico {
  id: string
  os_id: string
  evento: EventoOs
  observacao: string | null
  criado_em: string
}

export interface OsCustoContrato {
  contrato_id: string
  chamados: number
  custo_material: number
}

export const fmtMinutos = (m: number | null | undefined) => {
  if (m == null) return '—'
  const h = Math.floor(m / 60)
  return h > 0 ? `${h}h ${m % 60}min` : `${m}min`
}
