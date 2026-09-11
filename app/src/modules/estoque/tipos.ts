export interface EstoqueCategoria {
  id: string
  negocio_id: string
  nome: string
  descricao: string | null
  ativo: boolean
}

export const UNIDADES = ['unidade', 'metro', 'caixa', 'pacote', 'rolo', 'par'] as const
export type Unidade = (typeof UNIDADES)[number]

export interface EstoqueItem {
  id: string
  organizacao_id: string
  negocio_id: string
  categoria_id: string
  codigo: string
  nome: string
  descricao: string | null
  unidade_medida: Unidade
  marca: string | null
  modelo: string | null
  valor_custo: number
  valor_venda: number | null
  quantidade_atual: number
  quantidade_minima: number
  quantidade_maxima: number | null
  localizacao: string | null
  ativo: boolean
}

export type TipoMov = 'entrada' | 'saida' | 'ajuste'
export type OrigemMov = 'compra' | 'instalacao' | 'devolucao' | 'ajuste' | 'perda' | 'inventario' | 'transferencia'
export const ROTULO_ORIGEM: Record<OrigemMov, string> = {
  compra: 'Compra', instalacao: 'Instalação', devolucao: 'Devolução', ajuste: 'Ajuste', perda: 'Perda', inventario: 'Inventário', transferencia: 'Transferência (bolsa)',
}

export interface EstoqueMov {
  id: string
  item_id: string
  instalacao_id?: string | null
  tipo: TipoMov
  origem: OrigemMov
  quantidade: number
  valor_unitario: number
  valor_total: number
  data: string
  pessoa_id: string | null
  contrato_id: string | null
  lancamento_id: string | null
  observacao: string | null
  criado_em: string
}

export interface DadosItem {
  negocio_id: string
  categoria_id: string
  codigo: string
  nome: string
  descricao: string | null
  unidade_medida: Unidade
  marca: string | null
  modelo: string | null
  valor_venda: number | null
  quantidade_minima: number
  quantidade_maxima: number | null
  localizacao: string | null
  ativo: boolean
}

/** teveEntrada: item com ao menos uma entrada/ajuste positivo no histórico.
 *  Sem isso, item recém-criado com saldo 0 é "aguardando 1ª entrada", não alerta. */
export function statusItem(i: EstoqueItem, teveEntrada = true): { rotulo: string; tom: 'zerado' | 'baixo' | 'excesso' | 'ok' | 'novo' } {
  if (i.quantidade_atual === 0 && !teveEntrada) return { rotulo: 'Aguardando 1ª entrada', tom: 'novo' }
  if (i.quantidade_atual === 0) return { rotulo: 'Zerado', tom: 'zerado' }
  if (i.quantidade_atual <= i.quantidade_minima) return { rotulo: 'Baixo', tom: 'baixo' }
  if (i.quantidade_maxima != null && i.quantidade_maxima > 0 && i.quantidade_atual > i.quantidade_maxima) return { rotulo: 'Excesso', tom: 'excesso' }
  return { rotulo: 'Normal', tom: 'ok' }
}

export const fmtQtd = (n: number) => n.toLocaleString('pt-BR', { maximumFractionDigits: 2 })

export interface EstoqueInstalacao {
  id: string
  negocio_id: string
  pessoa_id: string
  contrato_id: string | null
  porta_id: string | null
  data: string
  custo_material: number
  mao_de_obra: number
  custo_total: number
  tecnico: string | null
  observacao: string | null
  criado_em: string
}

export interface ConsumoMensal {
  negocio_id: string
  mes: string
  tipo: TipoMov
  origem: OrigemMov
  movimentacoes: number
  quantidade: number
  valor_total: number
}

export interface ConsumoItem {
  negocio_id: string
  item_id: string
  mes: string
  quantidade: number
  valor_total: number
  movimentacoes: number
}

export type StatusComodato = 'instalado' | 'recolhido' | 'trocado' | 'perdido'
export const ROTULO_COMODATO: Record<StatusComodato, string> = { instalado: 'Instalado', recolhido: 'Recolhido', trocado: 'Trocado', perdido: 'Perdido' }

export interface Comodato {
  id: string
  negocio_id: string
  item_id: string
  numero_serie: string
  pessoa_id: string
  contrato_id: string | null
  tecnico_id: string | null
  status: StatusComodato
  data_instalacao: string
  data_recolhimento: string | null
  os_instalacao_id: string | null
  os_recolhimento_id: string | null
  observacao: string | null
}

// ---- Patrimônio (bens individuais, fora do estoque de consumo) ----
export type EstadoPatrimonio = 'novo' | 'bom' | 'regular' | 'ruim'
export type StatusPatrimonio = 'ativo' | 'vendido' | 'perdido' | 'descartado'
export const ROTULO_ESTADO_PAT: Record<EstadoPatrimonio, string> = { novo: 'Novo', bom: 'Bom', regular: 'Regular', ruim: 'Ruim' }
export const ROTULO_STATUS_PAT: Record<StatusPatrimonio, string> = { ativo: 'Ativo', vendido: 'Vendido', perdido: 'Perdido', descartado: 'Descartado' }

export interface Patrimonio {
  id: string
  organizacao_id: string
  negocio_id: string
  numero: number
  nome: string
  numero_serie: string | null
  valor_aquisicao: number
  data_aquisicao: string
  nota_fiscal: string | null
  localizacao: string
  estado: EstadoPatrimonio
  status: StatusPatrimonio
  observacao: string | null
  criado_em: string
}
export const codigoPatrimonio = (p: Pick<Patrimonio, 'numero'>) => `PAT-${String(p.numero).padStart(3, '0')}`

export interface PatrimonioHistorico { id: string; patrimonio_id: string; evento: string; detalhe: string; criado_em: string }
