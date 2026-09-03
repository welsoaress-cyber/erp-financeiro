export interface PortalConfigPublica { ativo: boolean; logo_url: string | null; cor_primaria: string; texto_promocional: string | null; chave_pix: string | null; instrucoes_pagamento: string | null; beneficio_indicacao: number }
export interface PortalResumo {
  pessoa: { id: string; nome: string; documento: string | null; email: string | null; telefone: string | null; receber_avisos: boolean }
  codigo_indicacao: string
  negocios: { id: string; nome: string; portal: PortalConfigPublica | null }[]
  em_aberto: number
  vencidas: number
  proximo_vencimento: string | null
  contratos_ativos: number
  indicacoes_convertidas: number
}
export type SituacaoFatura = 'paga' | 'vencida' | 'pendente' | 'cancelada'
export interface Fatura { id: string; negocio: string; contrato_codigo: number; plano: string; descricao: string; valor: number; data_vencimento: string; data_efetivacao: string | null; status: string; situacao: SituacaoFatura; observacao: string | null; chave_pix: string | null; instrucoes_pagamento: string | null }
export interface ProximaFatura { contrato_codigo: number; negocio: string; plano: string; competencia: string; data_vencimento: string; valor: number }
export interface Pagamento { id: string; data_pagamento: string; valor: number; descricao: string; negocio: string; contrato_codigo: number; forma: string }
export interface ContratoCliente { id: string; codigo: number; negocio: string; plano: string; plano_descricao: string | null; valor: number; periodicidade: 'mensal' | 'anual' | 'unico'; data_inicio: string; data_fim: string | null; dia_vencimento: number; status: 'ativo' | 'suspenso' | 'encerrado'; proxima_renovacao: string | null; descontos_pendentes: number }
export interface Promocao { id: string; negocio: string; titulo: string; descricao: string; regras: string | null; como_aderir: string | null; data_inicio: string; data_fim: string | null; plano: string | null }
export interface Indicacao { id: string; negocio: string; nome_indicado: string; status: 'pendente' | 'convertida' | 'cancelada'; beneficio_valor: number; criado_em: string }
export const ROTULO_SITUACAO: Record<SituacaoFatura, string> = { paga: 'Paga', vencida: 'Vencida', pendente: 'Em aberto', cancelada: 'Cancelada' }
export const ROTULO_STATUS_CONTRATO = { ativo: 'Ativo', suspenso: 'Suspenso', encerrado: 'Encerrado' } as const
export const ROTULO_INDICACAO = { pendente: 'Aguardando', convertida: 'Convertida', cancelada: 'Cancelada' } as const
export const codigoContrato = (n: number) => `#${String(n).padStart(3, '0')}`
export const linkIndicacao = (codigo: string) => `${window.location.origin}/portal/indicacao/${codigo}`
