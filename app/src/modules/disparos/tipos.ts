export interface DisparoModelo {
  id: string
  organizacao_id: string
  nome: string
  texto: string
  ativo: boolean
}

export type StatusDisparo = 'pendente' | 'enviado' | 'erro'
export const ROTULO_STATUS_DISPARO: Record<StatusDisparo, string> = { pendente: 'Pendente', enviado: 'Enviado', erro: 'Erro' }

export interface Disparo {
  id: string
  organizacao_id: string
  negocio_id: string
  modelo_nome: string
  criado_em: string
  /** resumo dos itens (vem aninhado na listagem) */
  disparo_itens?: { status: StatusDisparo; pessoa_id: string; vencimento: string | null }[]
}

export interface DisparoItem {
  id: string
  disparo_id: string
  pessoa_id: string
  numero_destino: string
  mensagem: string
  status: StatusDisparo
  tentativas: number
  erro: string | null
  data_envio: string | null
  vencimento: string | null
}

/** Lê o texto de todas as páginas de um PDF no navegador (pdfjs). */
export async function lerTextoPdf(buffer: ArrayBuffer): Promise<string> {
  const pdfjs = await import('pdfjs-dist')
  const worker = await import('pdfjs-dist/build/pdf.worker.min.mjs?url')
  pdfjs.GlobalWorkerOptions.workerSrc = worker.default
  const doc = await pdfjs.getDocument({ data: buffer }).promise
  const partes: string[] = []
  for (let p = 1; p <= doc.numPages; p++) {
    const pagina = await doc.getPage(p)
    const conteudo = await pagina.getTextContent()
    partes.push(conteudo.items.map((i) => ('str' in i ? i.str : '')).join(' '))
  }
  return partes.join('\n')
}
