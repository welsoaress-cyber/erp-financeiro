export interface ItemNFe {
  codigo: string
  descricao: string
  unidade: string
  quantidade: number
  valorUnitario: number
  valorTotal: number
}

export interface NotaFiscalParseada {
  chave: string
  numero: string
  serie: string
  dataEmissao: string | null // ISO (AAAA-MM-DD)
  autorizada: boolean
  situacao: string
  fornecedorCnpj: string | null
  fornecedorCpf: string | null
  fornecedorNome: string
  itens: ItemNFe[]
  valorTotal: number
}
