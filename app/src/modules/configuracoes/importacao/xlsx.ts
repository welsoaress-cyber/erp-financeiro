import type { Tabela } from './csv'

/** Lê a primeira planilha de um .xlsx/.xls como tabela de textos (datas viram DD/MM/AAAA).
 *  A biblioteca é carregada sob demanda para não pesar o bundle de quem só usa CSV. */
export async function lerXlsx(buffer: ArrayBuffer): Promise<Tabela> {
  const XLSX = await import('xlsx')
  const wb = XLSX.read(buffer, { type: 'array', cellDates: true })
  const ws = wb.Sheets[wb.SheetNames[0]]
  if (!ws) throw new Error('A planilha está vazia.')
  // raw: true preserva Date/número; a formatação para texto é nossa (o formato da célula
  // costuma ser americano, ex.: 9/1/26, que o importador rejeitaria)
  const matriz = XLSX.utils.sheet_to_json<unknown[]>(ws, { header: 1, raw: true, defval: '' })
  const celula = (c: unknown): string => {
    if (c instanceof Date) {
      const dd = String(c.getDate()).padStart(2, '0')
      const mm = String(c.getMonth() + 1).padStart(2, '0')
      return `${dd}/${mm}/${c.getFullYear()}`
    }
    return String(c ?? '').trim()
  }
  const linhas = matriz.map((l) => l.map(celula)).filter((l) => l.some((c) => c !== ''))
  if (linhas.length < 2) throw new Error('O arquivo não tem cabeçalho e linhas de dados.')
  return { cabecalho: linhas[0], linhas: linhas.slice(1), separador: ',' }
}
