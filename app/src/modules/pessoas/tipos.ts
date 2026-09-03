export const TIPOS_PESSOA = [
  { valor: 'fisica', rotulo: 'Pessoa física' },
  { valor: 'juridica', rotulo: 'Pessoa jurídica' },
] as const
export type TipoPessoa = (typeof TIPOS_PESSOA)[number]['valor']

export const PAPEIS_VINCULO = [
  { valor: 'cliente', rotulo: 'Cliente' },
  { valor: 'fornecedor', rotulo: 'Fornecedor' },
  { valor: 'parceiro', rotulo: 'Parceiro' },
  { valor: 'outro', rotulo: 'Outro' },
] as const
export type PapelVinculo = (typeof PAPEIS_VINCULO)[number]['valor']
export const ROTULO_PAPEL: Record<PapelVinculo, string> = Object.fromEntries(PAPEIS_VINCULO.map((p) => [p.valor, p.rotulo])) as Record<PapelVinculo, string>

export interface Pessoa {
  id: string
  organizacao_id: string
  tipo: TipoPessoa
  nome: string
  documento: string | null
  email: string | null
  telefone: string | null
  data_nascimento: string | null
  observacao: string | null
  ativo: boolean
  receber_avisos: boolean
  criado_em: string
  atualizado_em: string
}

export interface DadosPessoa {
  tipo: TipoPessoa
  nome: string
  documento: string | null
  email: string | null
  telefone: string | null
  data_nascimento: string | null
  observacao: string | null
  ativo: boolean
  receber_avisos: boolean
}

export interface Vinculo {
  id: string
  organizacao_id: string
  pessoa_id: string
  negocio_id: string
  papel: PapelVinculo
  ativo: boolean
  desde: string
}

export const somenteDigitos = (v: string) => v.replace(/\D/g, '')

export function formatarDocumento(doc: string | null): string {
  if (!doc) return '—'
  if (doc.length === 11) return doc.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, '$1.$2.$3-$4')
  if (doc.length === 14) return doc.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, '$1.$2.$3/$4-$5')
  return doc
}

export function formatarTelefone(tel: string | null): string {
  if (!tel) return ''
  if (tel.length === 11) return tel.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3')
  if (tel.length === 10) return tel.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3')
  return tel
}

/** Mesma regra do banco (dígitos verificadores de CPF e CNPJ). */
export function documentoValido(doc: string): boolean {
  if (!/^\d+$/.test(doc) || /^(\d)\1+$/.test(doc)) return false
  const d = doc.split('').map(Number)
  if (doc.length === 11) {
    const dv = (n: number) => { let s = 0; for (let i = 0; i < n; i++) s += d[i] * (n + 1 - i); const r = (s * 10) % 11; return r === 10 ? 0 : r }
    return dv(9) === d[9] && dv(10) === d[10]
  }
  if (doc.length === 14) {
    const dv = (n: number) => { let s = 0; for (let i = 0; i < n; i++) s += d[i] * (i < n - 8 ? n - 7 - i : n + 1 - i); const r = s % 11; return r < 2 ? 0 : 11 - r }
    return dv(12) === d[12] && dv(13) === d[13]
  }
  return false
}
