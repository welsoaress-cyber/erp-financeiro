export interface Negocio {
  id: string
  organizacao_id: string
  nome: string
  slug: string
  ativo: boolean
  conta_padrao_id: string | null
  categoria_receita_id: string | null
  criado_em: string
  atualizado_em: string
}

export interface DadosNegocio {
  nome: string
  slug: string
  ativo: boolean
  conta_padrao_id: string | null
  categoria_receita_id: string | null
}

/** "Navalha no Bigode" → "navalha-no-bigode". Sem acentos, minúsculas, hífens. */
export function gerarSlug(nome: string): string {
  return nome
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40)
}

export const SLUG_VALIDO = /^[a-z0-9]+(-[a-z0-9]+)*$/

/** Rótulo do negócio para listas e filtros; nulo = pessoal. */
export const ROTULO_PESSOAL = 'Pessoal'
