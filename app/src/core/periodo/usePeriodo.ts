import { useSyncExternalStore } from 'react'
import { mesAtualISO } from '../formatos'

/** Mês selecionado, compartilhado por todos os submódulos do Financeiro (persiste na aba). */
const CHAVE = 'erp.periodo.mes'
const ouvintes = new Set<() => void>()
let mesAtual = (() => { try { const v = sessionStorage.getItem(CHAVE); return v && /^\d{4}-\d{2}$/.test(v) ? v : mesAtualISO() } catch { return mesAtualISO() } })()
function definir(m: string) { mesAtual = m; try { sessionStorage.setItem(CHAVE, m) } catch { /* sem storage */ } ouvintes.forEach((f) => f()) }
const assinar = (f: () => void) => { ouvintes.add(f); return () => { ouvintes.delete(f) } }

export function usePeriodo() {
  const mes = useSyncExternalStore(assinar, () => mesAtual, () => mesAtual)
  return { mes, setMes: definir, ehMesAtual: mes === mesAtualISO(), voltarAoAtual: () => definir(mesAtualISO()) }
}
