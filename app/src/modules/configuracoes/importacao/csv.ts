/** Leitura de CSV no navegador: separador automático (; , tab), aspas, BOM, CRLF, UTF-8 ou Windows-1252. */
export interface Tabela {
  cabecalho: string[]
  linhas: string[][]
  separador: string
}

export function decodificar(buffer: ArrayBuffer): string {
  const utf8 = new TextDecoder('utf-8').decode(buffer)
  // arquivo do Excel/Windows: bytes inválidos em UTF-8 viram U+FFFD → tenta Windows-1252
  if (utf8.includes('�')) return new TextDecoder('windows-1252').decode(buffer)
  return utf8
}

export function detectarSeparador(texto: string): string {
  const primeira = texto.split(/\r?\n/, 1)[0] ?? ''
  const cont = (s: string) => primeira.split(s).length - 1
  return [';', ',', '\t'].sort((a, b) => cont(b) - cont(a))[0]
}

export function lerCsv(texto: string, separador = detectarSeparador(texto)): Tabela {
  const t = texto.replace(/^﻿/, '')
  const linhas: string[][] = []
  let atual: string[] = []
  let campo = ''
  let aspas = false
  for (let i = 0; i < t.length; i++) {
    const ch = t[i]
    if (aspas) {
      if (ch === '"') {
        if (t[i + 1] === '"') { campo += '"'; i++ } else aspas = false
      } else campo += ch
    } else if (ch === '"') aspas = true
    else if (ch === separador) { atual.push(campo); campo = '' }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && t[i + 1] === '\n') i++
      atual.push(campo); campo = ''
      linhas.push(atual); atual = []
    } else campo += ch
  }
  if (campo !== '' || atual.length) { atual.push(campo); linhas.push(atual) }
  const naoVazias = linhas.filter((l) => l.some((c) => c.trim() !== ''))
  const [cabecalho = [], ...resto] = naoVazias
  return { cabecalho: cabecalho.map((c) => c.trim()), linhas: resto, separador }
}

/** Campos que a importação entende. Cada um é mapeado para uma coluna do CSV. */
export const CAMPOS = [
  { chave: 'nome', rotulo: 'Nome', obrigatorio: true, pistas: ['nome', 'cliente', 'razao'] },
  { chave: 'documento', rotulo: 'CPF/CNPJ (opcional)', obrigatorio: false, pistas: ['cpf/cnpj', 'cpf', 'documento', 'doc', 'cnpj'] },
  { chave: 'documento2', rotulo: 'CNPJ (se estiver em outra coluna)', obrigatorio: false, pistas: ['cnpj'] },
  { chave: 'telefone', rotulo: 'Telefone (vazio = sem aviso WhatsApp)', obrigatorio: false, pistas: ['telefone', 'celular', 'fone', 'whatsapp'] },
  { chave: 'email', rotulo: 'E-mail', obrigatorio: false, pistas: ['email', 'e-mail'] },
  { chave: 'plano', rotulo: 'Plano (vazio = nome do negócio)', obrigatorio: false, pistas: ['plano', 'velocidade', 'servico', 'produto'] },
  { chave: 'valor', rotulo: 'Valor da cobrança', obrigatorio: false, pistas: ['valor', 'mensalidade', 'preco'] },
  { chave: 'periodicidade', rotulo: 'Periodicidade (mensal, bimestral…)', obrigatorio: false, pistas: ['periodicidade', 'ciclo', 'frequencia'] },
  { chave: 'dia_vencimento', rotulo: 'Vencimento (vazio = dia 10)', obrigatorio: false, pistas: ['vencimento', 'dia'] },
  { chave: 'data_inicio', rotulo: 'Data de início (vazio = hoje)', obrigatorio: false, pistas: ['inicio', 'início', 'cobranca', 'cadastro', 'adesao'] },
  { chave: 'data_fim', rotulo: 'Data do cancelamento', obrigatorio: false, pistas: ['cancelamento', 'cancel', 'fim', 'encerramento'] },
] as const
export type ChaveCampo = (typeof CAMPOS)[number]['chave']
export type Mapeamento = Record<ChaveCampo, number | null>

const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

/** Sugere o mapeamento pelo nome das colunas. Cada coluna é usada uma vez. */
export function sugerirMapeamento(cabecalho: string[]): Mapeamento {
  const usadas = new Set<number>()
  const cols = cabecalho.map(normalizar)
  const m = {} as Mapeamento
  for (const campo of CAMPOS) {
    let achado: number | null = null
    for (const pista of campo.pistas) {
      const i = cols.findIndex((c, idx) => !usadas.has(idx) && c.includes(normalizar(pista)))
      if (i >= 0) { achado = i; break }
    }
    if (achado !== null) usadas.add(achado)
    m[campo.chave] = achado
  }
  return m
}

/** Linha do CSV convertida para o formato que a RPC `importar_clientes` recebe. */
export interface LinhaImportacao {
  linha: number
  nome: string
  documento: string
  telefone: string
  email: string
  plano: string
  valor: string
  periodicidade: string
  dia_vencimento: string
  data_inicio: string
  data_fim: string
}

/** Aceita o dia (10) ou uma data completa (10/09/2026, 2026-09-10) e devolve só o dia. */
export function diaDeVencimento(v: string): string {
  const t = v.trim()
  const br = /^(\d{1,2})\/(\d{1,2})\/(\d{2,4})/.exec(t); if (br) return String(Number(br[1]))
  const iso = /^\d{4}-\d{2}-(\d{2})/.exec(t); if (iso) return String(Number(iso[1]))
  return t.replace(/\D/g, '')
}

export function montarLinhas(tabela: Tabela, m: Mapeamento): LinhaImportacao[] {
  const pega = (l: string[], i: number | null) => (i === null ? '' : (l[i] ?? '').trim())
  return tabela.linhas.map((l, idx) => ({
    linha: idx + 2, // 1 = cabeçalho
    nome: pega(l, m.nome),
    documento: pega(l, m.documento) || pega(l, m.documento2),  // CPF ou CNPJ em colunas separadas
    telefone: pega(l, m.telefone),
    email: pega(l, m.email),
    plano: pega(l, m.plano),
    valor: pega(l, m.valor),
    periodicidade: pega(l, m.periodicidade) || 'mensal',
    dia_vencimento: diaDeVencimento(pega(l, m.dia_vencimento)),
    data_inicio: pega(l, m.data_inicio),
    data_fim: pega(l, m.data_fim),
  }))
}

/** "Velocidade_0100_MB" → "Plano 100 Mbps" (mesma regra do banco, só para a prévia). */
export function nomePlanoImportado(nome: string): string {
  const m = /^\s*velocidade[_ ]0*(\d+)[_ ]?mb\s*$/i.exec(nome)
  return m ? `Plano ${m[1]} Mbps` : nome.trim().replace(/\s+/g, ' ')
}
