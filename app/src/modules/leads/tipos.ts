export const STATUS_LEAD = ['novo', 'contatado', 'qualificado', 'negociando', 'fechado', 'perdido'] as const
export type StatusLead = (typeof STATUS_LEAD)[number]
export const ROTULO_STATUS_LEAD: Record<StatusLead, string> = {
  novo: 'Novo',
  contatado: 'Contatado',
  qualificado: 'Qualificado',
  negociando: 'Negociando',
  fechado: 'Fechado',
  perdido: 'Perdido',
}
/** Etapas do funil, em ordem — 'fechado' e 'perdido' são desfechos, ficam fora do funil ativo. */
export const ETAPAS_FUNIL: StatusLead[] = ['novo', 'contatado', 'qualificado', 'negociando']

export const ORIGENS_LEAD = ['site', 'whatsapp', 'indicacao', 'manual', 'api'] as const
export type OrigemLead = (typeof ORIGENS_LEAD)[number]
export const ROTULO_ORIGEM_LEAD: Record<OrigemLead, string> = {
  site: 'Site',
  whatsapp: 'WhatsApp',
  indicacao: 'Indicação',
  manual: 'Manual',
  api: 'API',
}

export const TIPOS_INTERACAO_LEAD = ['ligacao', 'whatsapp', 'email', 'visita'] as const
export type TipoInteracaoLead = (typeof TIPOS_INTERACAO_LEAD)[number]
export const ROTULO_INTERACAO_LEAD: Record<TipoInteracaoLead, string> = {
  ligacao: 'Ligação',
  whatsapp: 'WhatsApp',
  email: 'E-mail',
  visita: 'Visita',
}

export interface Lead {
  id: string
  organizacao_id: string
  negocio_id: string
  nome: string
  telefone: string
  email: string | null
  endereco: string | null
  origem: OrigemLead
  plano_interesse_id: string | null
  status: StatusLead
  observacao: string | null
  convertido_pessoa_id: string | null
  convertido_em: string | null
  criado_em: string
  atualizado_em: string
}

export interface DadosLead {
  negocio_id: string
  nome: string
  telefone: string
  email: string | null
  endereco: string | null
  plano_interesse_id: string | null
  observacao: string | null
}

export interface LeadEvento {
  id: string
  lead_id: string
  tipo: TipoInteracaoLead
  descricao: string | null
  usuario_id: string | null
  criado_em: string
}
