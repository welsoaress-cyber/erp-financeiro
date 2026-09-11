import type { DefinicaoModulo } from '../modulos/tipos'

const CHAVE = 'erp.menu.ordem'

/** Ordem personalizada do menu, salva por navegador. */
export function lerOrdem(): string[] {
  try {
    const bruto = localStorage.getItem(CHAVE)
    const lista = bruto ? (JSON.parse(bruto) as unknown) : null
    return Array.isArray(lista) ? lista.filter((x): x is string => typeof x === 'string') : []
  } catch {
    return []
  }
}

export function salvarOrdem(ids: string[]) {
  try {
    localStorage.setItem(CHAVE, JSON.stringify(ids))
  } catch {
    // sem storage (aba anônima) — a ordem vale só até recarregar
  }
}

/** Aplica a ordem salva; módulos novos (fora da lista) entram no fim, na ordem padrão. */
export function aplicarOrdem(modulos: DefinicaoModulo[], ordem: string[]): DefinicaoModulo[] {
  if (ordem.length === 0) return modulos
  const posicao = new Map(ordem.map((id, i) => [id, i]))
  return [...modulos].sort(
    (a, b) =>
      (posicao.get(a.id) ?? ordem.length + modulos.indexOf(a)) -
      (posicao.get(b.id) ?? ordem.length + modulos.indexOf(b)),
  )
}
