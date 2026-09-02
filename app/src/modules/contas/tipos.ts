export const TIPOS_CONTA = [
  { valor: 'corrente', rotulo: 'Conta corrente' },
  { valor: 'poupanca', rotulo: 'Poupança' },
  { valor: 'dinheiro', rotulo: 'Dinheiro' },
  { valor: 'carteira_digital', rotulo: 'Carteira digital' },
  { valor: 'investimento', rotulo: 'Investimento' },
] as const

export type TipoConta = (typeof TIPOS_CONTA)[number]['valor']

export const ROTULO_TIPO: Record<TipoConta, string> = Object.fromEntries(
  TIPOS_CONTA.map((t) => [t.valor, t.rotulo]),
) as Record<TipoConta, string>

export interface Conta {
  id: string
  organizacao_id: string
  nome: string
  tipo: TipoConta
  saldo_inicial: number
  data_inicio: string
  ativo: boolean
  /** Derivado: saldo_inicial + Σ movimentos efetivados (vw_saldo_contas). */
  saldo: number
  movimentos: number
  negocio_id: string | null
}

export interface DadosConta {
  nome: string
  tipo: TipoConta
  saldo_inicial: number
  data_inicio: string
  ativo: boolean
  negocio_id: string | null
}
