import type { ItemNFe, NotaFiscalParseada } from './tipos'

function txt(el: Element | Document, tag: string): string {
  return el.getElementsByTagName(tag)[0]?.textContent?.trim() ?? ''
}
function num(el: Element | Document, tag: string): number {
  return Number(txt(el, tag).replace(',', '.')) || 0
}
const soDigitos = (s: string) => s.replace(/\D/g, '')

function parseNFeProduto(doc: Document, infNFe: Element): NotaFiscalParseada {
  const idAttr = infNFe.getAttribute('Id') ?? ''
  const chaveProt = txt(doc, 'chNFe')
  const chave = soDigitos(chaveProt || idAttr).slice(-44)
  if (chave.length !== 44) throw new Error('Não encontrei a chave de acesso (44 dígitos) no XML.')

  const cStat = txt(doc, 'cStat')
  const xMotivo = txt(doc, 'xMotivo')

  const emit = infNFe.getElementsByTagName('emit')[0]
  const fornecedorCnpj = emit ? soDigitos(txt(emit, 'CNPJ')) || null : null
  const fornecedorCpf = emit ? soDigitos(txt(emit, 'CPF')) || null : null
  const fornecedorNome = emit ? (txt(emit, 'xFant') || txt(emit, 'xNome')) : ''

  const dhEmi = txt(doc, 'dhEmi')
  const dataEmissao = dhEmi ? dhEmi.slice(0, 10) : null

  const itens: ItemNFe[] = Array.from(infNFe.getElementsByTagName('det')).map((det) => {
    const prod = det.getElementsByTagName('prod')[0]
    const quantidade = prod ? num(prod, 'qCom') : 0
    const valorTotal = prod ? num(prod, 'vProd') : 0
    const valorUnitario = prod ? num(prod, 'vUnCom') : (quantidade > 0 ? valorTotal / quantidade : 0)
    return {
      codigo: prod ? txt(prod, 'cProd') : '',
      descricao: prod ? txt(prod, 'xProd') : '',
      unidade: prod ? txt(prod, 'uCom') : 'UN',
      quantidade,
      valorUnitario,
      valorTotal,
    }
  })

  return {
    chave,
    numero: txt(doc, 'nNF'),
    serie: txt(doc, 'serie'),
    dataEmissao,
    autorizada: cStat === '100',
    situacao: xMotivo || (cStat ? `Status ${cStat}` : 'Status desconhecido'),
    fornecedorCnpj,
    fornecedorCpf,
    fornecedorNome,
    itens,
    valorTotal: num(doc, 'vNF'),
  }
}

/** NFS-e (nota de serviço, prefeitura) — layout ABRASF; sem chave de 44 dígitos, usa Número + Código de verificação. */
function parseNFSe(infNfse: Element): NotaFiscalParseada {
  const numero = txt(infNfse, 'Numero')
  const codigoVerificacao = txt(infNfse, 'CodigoVerificacao')
  if (!numero || !codigoVerificacao) throw new Error('XML de NFS-e sem número ou código de verificação.')

  const prestador = infNfse.getElementsByTagName('PrestadorServico')[0]
  const cnpjPrestador = prestador ? soDigitos(txt(prestador, 'Cnpj')) || null : null
  const fornecedorNome = prestador ? (txt(prestador, 'NomeFantasia') || txt(prestador, 'RazaoSocial')) : ''

  const dataEmissao = txt(infNfse, 'DataEmissao')
  const servico = infNfse.getElementsByTagName('Servico')[0]
  const discriminacao = servico ? txt(servico, 'Discriminacao') : 'Serviço'
  const valorServicos = servico ? num(servico, 'ValorServicos') : 0
  const valorLiquido = num(infNfse, 'ValorLiquidoNfse') || valorServicos

  const status = infNfse.getElementsByTagName('Rps')[0]?.getElementsByTagName('Status')[0]?.textContent?.trim()
  const cancelada = status != null && status !== '1'

  return {
    chave: `NFSE-${cnpjPrestador ?? '0'}-${numero}-${codigoVerificacao}`,
    numero,
    serie: '',
    dataEmissao: dataEmissao ? dataEmissao.slice(0, 10) : null,
    autorizada: !cancelada,
    situacao: cancelada ? `Status ${status}` : 'NFS-e normal',
    fornecedorCnpj: cnpjPrestador,
    fornecedorCpf: null,
    fornecedorNome,
    itens: [{ codigo: '', descricao: discriminacao, unidade: 'UN', quantidade: 1, valorUnitario: valorServicos, valorTotal: valorServicos }],
    valorTotal: valorLiquido,
  }
}

/** Lê o XML de uma nota fiscal (NFe de produto ou NFS-e de serviço) 100% no navegador — sem subir nada. */
export function parseNFeXml(xmlText: string): NotaFiscalParseada {
  const doc = new DOMParser().parseFromString(xmlText, 'application/xml')
  const erro = doc.getElementsByTagName('parsererror')[0]
  if (erro) throw new Error('Arquivo não é um XML válido.')

  const infNFe = doc.getElementsByTagName('infNFe')[0]
  if (infNFe) return parseNFeProduto(doc, infNFe)

  const infNfse = doc.getElementsByTagName('InfNfse')[0]
  if (infNfse) return parseNFSe(infNfse)

  throw new Error('XML não parece ser uma Nota Fiscal Eletrônica (NFe) nem uma NFS-e de serviço.')
}
