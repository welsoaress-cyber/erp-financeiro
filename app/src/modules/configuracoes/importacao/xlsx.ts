import type { Tabela } from './csv'

/** Lê a primeira planilha de um .xlsx/.xls como tabela de textos (datas viram DD/MM/AAAA).
 *  A biblioteca é carregada sob demanda para não pesar o bundle de quem só usa CSV. */
export async function lerXlsx(buffer: ArrayBuffer): Promise<Tabela> {
  const XLSX = await import('xlsx')
  const wb = XLSX.read(buffer, { type: 'array', cellDates: true })
  const ws = wb.Sheets[wb.SheetNames[0]]
  if (!ws) throw new Error('A planilha está vazia.')
  const matriz = XLSX.utils.sheet_to_json<unknown[]>(ws, { header: 1, raw: false, dateNF: 'dd/mm/yyyy', defval: '' })
  const linhas = matriz.map((l) => l.map((c) => String(c ?? '').trim())).filter((l) => l.some((c) => c !== ''))
  if (linhas.length < 2) throw new Error('O arquivo não tem cabeçalho e linhas de dados.')
  return { cabecalho: linhas[0], linhas: linhas.slice(1), separador: ',' }
}
