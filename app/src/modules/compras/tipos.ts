export type StatusRequisicao = 'pendente' | 'aprovada' | 'rejeitada' | 'convertida' | 'cancelada'
export type StatusPedido = 'aberto' | 'recebido_parcial' | 'recebido' | 'cancelado'
export type DestinoCompra = 'estoque' | 'despesa' | 'patrimonio' | 'comodato' | 'servico'

export const ROTULO_STATUS_REQ: Record<StatusRequisicao, string> = {
  pendente: 'Pendente', aprovada: 'Aprovada', rejeitada: 'Rejeitada', convertida: 'Convertida em pedido', cancelada: 'Cancelada',
}
export const ROTULO_STATUS_PEDIDO: Record<StatusPedido, string> = {
  aberto: 'Em aberto', recebido_parcial: 'Recebido parcial', recebido: 'Recebido', cancelado: 'Cancelado',
}
export const ROTULO_DESTINO: Record<DestinoCompra, string> = {
  estoque: 'Estoque', despesa: 'Despesa', patrimonio: 'Patrimônio', comodato: 'Comodato', servico: 'Serviço',
}

export interface Requisicao {
  id: string
  organizacao_id: string
  negocio_id: string
  numero: number
  solicitante_id: string
  justificativa: string | null
  status: StatusRequisicao
  aprovador_id: string | null
  decidido_em: string | null
  motivo_rejeicao: string | null
  pedido_id: string | null
  criado_em: string
}

export interface RequisicaoItem {
  id: string
  requisicao_id: string
  ordem: number
  item_id: string | null
  descricao: string
  quantidade: number
  destino: DestinoCompra
  observacao: string | null
}

export interface Pedido {
  id: string
  organizacao_id: string
  negocio_id: string
  requisicao_id: string | null
  fornecedor_id: string | null
  numero: number
  data_pedido: string
  previsao_entrega: string | null
  condicao_pagamento: string | null
  valor_frete: number
  valor_desconto: number
  observacao: string | null
  status: StatusPedido
}

export interface PedidoItem {
  id: string
  compra_id: string
  item_id: string | null
  descricao: string
  quantidade: number
  valor_unitario: number
  destino: DestinoCompra
  categoria_id: string | null
  contrato_id: string | null
  quantidade_recebida: number
  observacao: string | null
}

export interface CompraTotais { compra_id: string; total_itens: number; total_recebido: number; total_final: number }

export const codigoRequisicao = (r: Pick<Requisicao, 'numero'>) => `REQ-${String(r.numero).padStart(4, '0')}`
export const codigoPedido = (p: Pick<Pedido, 'numero'>) => `PED-${String(p.numero).padStart(4, '0')}`

export interface Recebimento {
  id: string
  organizacao_id: string
  compra_id: string
  data: string
  conferido_por: string | null
  nota_numero: string | null
  nota_chave: string | null
  nota_valor: number | null
  lancamento_id: string | null
  observacao: string | null
  criado_em: string
}

export interface RecebimentoItem {
  id: string
  recebimento_id: string
  compra_item_id: string
  quantidade: number
  numero_serie: string | null
  observacao: string | null
}
