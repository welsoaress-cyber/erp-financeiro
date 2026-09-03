export type TemaPortal = 'escuro' | 'claro'
export interface PortalConfigPublica { ativo: boolean; logo_url: string | null; cor_primaria: string; texto_promocional: string | null; chave_pix: string | null; instrucoes_pagamento: string | null; beneficio_indicacao: number; tema: TemaPortal; whatsapp_suporte: string | null; beneficio_tipo: 'valor' | 'mes_gratis'; fidelidade_ativa: boolean; site_url: string | null }
export interface PortalResumo {
  pessoa: { id: string; nome: string; documento: string | null; email: string | null; telefone: string | null; receber_avisos: boolean; tem_nascimento?: boolean }
  codigo_indicacao: string
  negocios: { id: string; nome: string; portal: PortalConfigPublica | null }[]
  em_aberto: number
  vencidas: number
  proximo_vencimento: string | null
  contratos_ativos: number
  indicacoes_convertidas: number
}
export type SituacaoFatura = 'paga' | 'vencida' | 'pendente' | 'cancelada' | 'gratis'
export interface Fatura { id: string; negocio: string; contrato_codigo: number; plano: string; descricao: string; valor: number; data_vencimento: string; data_efetivacao: string | null; status: string; situacao: SituacaoFatura; observacao: string | null; chave_pix: string | null; instrucoes_pagamento: string | null }
export interface ProximaFatura { contrato_codigo: number; negocio: string; plano: string; competencia: string; data_vencimento: string; valor: number }
export interface Pagamento { id: string; data_pagamento: string; valor: number; descricao: string; negocio: string; contrato_codigo: number; forma: string }
export interface ContratoCliente { id: string; codigo: number; negocio: string; plano: string; plano_descricao: string | null; valor: number; periodicidade: 'mensal' | 'anual' | 'unico'; data_inicio: string; data_fim: string | null; dia_vencimento: number; status: 'ativo' | 'suspenso' | 'encerrado'; proxima_renovacao: string | null; descontos_pendentes: number }
export interface Promocao { id: string; negocio: string; titulo: string; descricao: string; regras: string | null; como_aderir: string | null; data_inicio: string; data_fim: string | null; plano: string | null }
export interface Indicacao { id: string; negocio: string; nome_indicado: string; status: 'pendente' | 'convertida' | 'cancelada'; beneficio_valor: number; criado_em: string }
export type EstadoSelo = 'ok' | 'gratis' | 'atraso' | 'vencida' | 'aberto' | 'vazio'
export interface SeloFidelidade { n: number; competencia: string; estado: EstadoSelo; vencimento: string | null; valor: number | null }
export interface Fidelidade { contrato_id: string; codigo: number; negocio: string; plano: string; valor: number; ativa: boolean; inicio: string; fim: string; ciclo: number; selos: number; slots: SeloFidelidade[]; premios: { percentual: number; competencia: string; referencia: string }[] }
export type StatusRede = 'ok' | 'lentidao' | 'queda' | 'manutencao'
export interface AvisoRede { negocio_id: string; negocio: string; status: StatusRede; titulo: string | null; descricao: string | null; atualizado_em: string }
export type TipoSolicitacao = 'suporte' | 'fatura' | 'duvida' | 'upgrade'
export interface Solicitacao { id: string; negocio: string; tipo: TipoSolicitacao; descricao: string | null; protocolo: string; status: 'aberta' | 'em_andamento' | 'concluida'; resposta: string | null; criado_em: string }
export const ROTULO_SITUACAO: Record<SituacaoFatura, string> = { paga: 'Paga', vencida: 'Vencida', pendente: 'Em aberto', cancelada: 'Cancelada', gratis: 'Mês grátis' }
export const ROTULO_STATUS_CONTRATO = { ativo: 'Ativo', suspenso: 'Suspenso', encerrado: 'Encerrado' } as const
export const ROTULO_INDICACAO = { pendente: 'Aguardando', convertida: 'Convertida', cancelada: 'Cancelada' } as const
export const ROTULO_REDE: Record<StatusRede, string> = { ok: 'Rede operando normalmente', lentidao: 'Lentidão na rede', queda: 'Queda na rede', manutencao: 'Manutenção programada' }
export const ROTULO_TIPO_SOLICITACAO: Record<TipoSolicitacao, string> = { suporte: 'Suporte técnico', fatura: 'Fatura / pagamento', duvida: 'Dúvida', upgrade: 'Upgrade de plano' }
export const ROTULO_STATUS_SOLICITACAO = { aberta: 'Aberto', em_andamento: 'Em andamento', concluida: 'Concluído' } as const
export const codigoContrato = (n: number) => `#${String(n).padStart(3, '0')}`
/** Link público de indicação: usa o site do provedor quando configurado (ex.: https://www.servnet.net.br), senão o próprio portal. */
export const linkIndicacao = (codigo: string, siteUrl?: string | null) => siteUrl ? `${siteUrl.replace(/\/$/, '')}/?ref=${codigo}` : `${window.location.origin}/portal/indicacao/${codigo}`
export const linkWhatsApp = (numero: string, texto?: string) => `https://wa.me/${numero.replace(/\D/g, '')}${texto ? `?text=${encodeURIComponent(texto)}` : ''}`
export const TOM: Record<SituacaoFatura, 'ok' | 'alerta' | 'neutro' | 'info'> = { paga: 'ok', vencida: 'alerta', pendente: 'info', cancelada: 'neutro', gratis: 'ok' }
