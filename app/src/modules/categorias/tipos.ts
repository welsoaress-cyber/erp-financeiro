export const TIPOS_CATEGORIA = [
  { valor: 'receita', rotulo: 'Receita' },
  { valor: 'despesa', rotulo: 'Despesa' },
] as const

export type TipoCategoria = (typeof TIPOS_CATEGORIA)[number]['valor']

export interface Categoria {
  id: string
  organizacao_id: string
  nome: string
  tipo: TipoCategoria
  categoria_pai_id: string | null
  ativo: boolean
  criado_em: string
  atualizado_em: string
}

export interface DadosCategoria {
  nome: string
  tipo: TipoCategoria
  categoria_pai_id: string | null
  ativo: boolean
}

/** Agrupa em árvore de 2 níveis: raízes com suas subcategorias, ambas em ordem alfabética. */
export function montarArvore(categorias: Categoria[]): Array<{ raiz: Categoria; filhas: Categoria[] }> {
  const porNome = (a: Categoria, b: Categoria) => a.nome.localeCompare(b.nome, 'pt-BR')
  const raizes = categorias.filter((c) => c.categoria_pai_id === null).sort(porNome)
  return raizes.map((raiz) => ({
    raiz,
    filhas: categorias.filter((c) => c.categoria_pai_id === raiz.id).sort(porNome),
  }))
}
