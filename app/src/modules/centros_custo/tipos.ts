export type TipoCentroCusto = 'departamento' | 'projeto' | 'ponto_rede' | 'outro'
export const ROTULO_TIPO_CENTRO: Record<TipoCentroCusto, string> = { departamento: 'Departamento', projeto: 'Projeto', ponto_rede: 'Ponto de rede (POP/CEO/CTO)', outro: 'Outro' }

/** Centro de custo dentro do negócio (etapa 54A). Nulo no lançamento = "Geral". */
export interface CentroCusto {
  id: string
  organizacao_id: string
  negocio_id: string
  nome: string
  descricao: string | null
  tipo: TipoCentroCusto
  referencia_id: string | null
  ativo: boolean
  criado_em: string
  atualizado_em: string
}

export interface DadosCentroCusto {
  negocio_id: string
  nome: string
  descricao: string | null
  tipo: TipoCentroCusto
  referencia_id: string | null
  ativo: boolean
}
