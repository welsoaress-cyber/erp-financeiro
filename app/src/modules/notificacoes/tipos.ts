export type ProvedorNotificacao = 'simulado' | 'evolution'
export const PROVEDORES = [
  { valor: 'simulado', rotulo: 'Simulado (não envia)' },
  { valor: 'evolution', rotulo: 'Evolution API (envio real)' },
] as const
export const ROTULO_PROVEDOR: Record<ProvedorNotificacao, string> = { simulado: 'Simulado', evolution: 'Evolution API' }

export type TipoNotificacao = 'proximo_vencimento' | 'vencimento' | 'bloqueio' | 'teste'
export type StatusNotificacao = 'pendente' | 'simulado' | 'enviado' | 'erro'
export const ROTULO_TIPO: Record<TipoNotificacao, string> = { proximo_vencimento: 'Próximo ao vencimento', vencimento: 'Vencimento', bloqueio: 'Bloqueio', teste: 'Teste' }
export const ROTULO_STATUS: Record<StatusNotificacao, string> = { pendente: 'Pendente', simulado: 'Simulado', enviado: 'Enviado', erro: 'Erro' }
export const TIPOS_TESTE = [
  { valor: 'proximo_vencimento', rotulo: 'Próximo ao vencimento' },
  { valor: 'vencimento', rotulo: 'Vencimento' },
  { valor: 'bloqueio', rotulo: 'Bloqueio' },
] as const

export interface ConfigNotificacao {
  id: string
  organizacao_id: string
  negocio_id: string
  numero_whatsapp: string | null
  provedor: ProvedorNotificacao
  instancia: string | null
  ativo: boolean
  dias_antes: number
  dias_apos: number
  hora_inicio: string
  hora_fim: string
  template_vencimento_proximo: string
  template_vencimento_dia: string
  template_bloqueio: string
}

export interface DadosConfigNotificacao {
  numero_whatsapp: string | null
  provedor: ProvedorNotificacao
  instancia: string | null
  ativo: boolean
  dias_antes: number
  dias_apos: number
  hora_inicio: string
  hora_fim: string
  template_vencimento_proximo: string
  template_vencimento_dia: string
  template_bloqueio: string
}

export interface Notificacao {
  id: string
  negocio_id: string
  negocio: string
  contrato_id: string | null
  contrato_codigo: number | null
  pessoa_id: string
  pessoa: string
  lancamento_id: string | null
  tipo: TipoNotificacao
  data_referencia: string
  numero_destino: string | null
  mensagem: string
  status: StatusNotificacao
  provedor: string
  erro: string | null
  data_envio: string | null
  criado_em: string
}

export interface ResultadoExecucao { data: string; geradas: number; processadas: number; pendentes: number }

export const PLACEHOLDERS = ['{nome}', '{negocio}', '{plano}', '{valor}', '{vencimento}', '{contrato}', '{dias}'] as const

/** Prévia local do template (mesma regra do banco). */
export function renderizar(template: string, vars: Record<string, string>): string {
  return Object.entries(vars).reduce((t, [k, v]) => t.split(`{${k}}`).join(v), template)
}

export const TEMPLATES_PADRAO: Pick<DadosConfigNotificacao, 'template_vencimento_proximo' | 'template_vencimento_dia' | 'template_bloqueio'> = {
  template_vencimento_proximo: 'Olá {nome}! Sua fatura do {negocio} ({plano}) no valor de {valor} vence em {vencimento}. Qualquer dúvida, fale com a gente.',
  template_vencimento_dia: 'Olá {nome}! Sua fatura do {negocio} ({plano}) no valor de {valor} vence hoje, {vencimento}. Evite o bloqueio pagando ainda hoje.',
  template_bloqueio: 'Olá {nome}. Não identificamos o pagamento da fatura do {negocio} ({plano}), {valor}, vencida em {vencimento}. Seu acesso será bloqueado. Se já pagou, desconsidere.',
}
