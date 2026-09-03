import { useMemo, useState } from 'react'
import { Cartao } from '../../../core/ui/Cartao'
import { formatarMoeda } from '../../../core/formatos'
import type { Lancamento } from '../../lancamentos/tipos'
import { ROTULO_PESSOAL } from '../../negocios/tipos'
import type { SaldoInicialNegocio } from '../api'

interface Grupo { receitaPrevista: number; receitaRealizada: number; despesaPrevista: number; despesaRealizada: number; saldoInicial: number }
const GRUPO_ZERO: Grupo = { receitaPrevista: 0, receitaRealizada: 0, despesaPrevista: 0, despesaRealizada: 0, saldoInicial: 0 }
function somar(a: Grupo, b: Grupo): Grupo {
  return { receitaPrevista: a.receitaPrevista + b.receitaPrevista, receitaRealizada: a.receitaRealizada + b.receitaRealizada, despesaPrevista: a.despesaPrevista + b.despesaPrevista, despesaRealizada: a.despesaRealizada + b.despesaRealizada, saldoInicial: a.saldoInicial + b.saldoInicial }
}
function Linha({ rotulo, previsto, realizado, tom }: { rotulo: string; previsto: number; realizado: number; tom: 'receita' | 'despesa' }) {
  const cor = tom === 'receita' ? 'text-green-700' : 'text-red-700'
  return (
    <tr className="border-b border-line last:border-0">
      <td className="px-4 py-2 font-medium">{rotulo}</td>
      <td className="px-4 py-2 text-right tabular-nums text-ink-muted">{formatarMoeda(previsto)}</td>
      <td className={`px-4 py-2 text-right font-medium tabular-nums ${cor}`}>{formatarMoeda(realizado)}</td>
      <td className={`px-4 py-2 text-right font-medium tabular-nums ${cor}`}>{formatarMoeda(previsto + realizado)}</td>
    </tr>
  )
}

/** Resumo Financeiro do Período: saldo inicial, receitas e despesas (previsto × realizado) e
 * resultado, consolidado ou por negócio. Baseado nos mesmos lançamentos do mês do Financeiro. */
export function ResumoFinanceiro({ lancamentos, saldoInicial, negocioPorId, filtro, bate }: {
  lancamentos: Lancamento[]
  saldoInicial: SaldoInicialNegocio[]
  negocioPorId: Map<string, string>
  filtro: string
  bate: (negocioId: string | null) => boolean
}) {
  const [expandido, setExpandido] = useState(false)
  const grupos = useMemo(() => {
    const m = new Map<string, Grupo>()
    const chave = (id: string | null) => id ?? 'pessoal'
    for (const s of saldoInicial) {
      const k = chave(s.negocio_id)
      m.set(k, somar(m.get(k) ?? GRUPO_ZERO, { ...GRUPO_ZERO, saldoInicial: s.saldo }))
    }
    for (const l of lancamentos) {
      if (l.status === 'cancelado' || l.tipo === 'transferencia') continue
      const k = chave(l.negocio_id)
      const g = { ...GRUPO_ZERO, ...(m.get(k) ?? {}) }
      if (l.tipo === 'receita') { if (l.status === 'previsto') g.receitaPrevista += l.valor; else g.receitaRealizada += l.valor }
      else if (l.status === 'previsto') g.despesaPrevista += l.valor; else g.despesaRealizada += l.valor
      m.set(k, g)
    }
    return m
  }, [lancamentos, saldoInicial])
  const nomeDe = (k: string) => (k === 'pessoal' ? ROTULO_PESSOAL : negocioPorId.get(k) ?? '—')
  const linhas = [...grupos.keys()].filter((k) => bate(k === 'pessoal' ? null : k)).sort((a, b) => nomeDe(a).localeCompare(nomeDe(b), 'pt-BR'))
  const totalGeral = linhas.reduce((t, k) => somar(t, grupos.get(k) ?? GRUPO_ZERO), GRUPO_ZERO)
  const mostrarDetalhe = !filtro && linhas.length > 1
  const saldoFinal = totalGeral.saldoInicial + totalGeral.receitaPrevista + totalGeral.receitaRealizada - totalGeral.despesaPrevista - totalGeral.despesaRealizada

  return (
    <Cartao className="p-0">
      <div className="flex items-center justify-between border-b border-line px-6 py-3">
        <h2 className="text-sm font-semibold">Resumo financeiro do período</h2>
        {mostrarDetalhe && <button type="button" onClick={() => setExpandido((v) => !v)} className="text-xs font-medium text-brand-600 hover:underline">{expandido ? 'Ver total consolidado' : 'Detalhar por negócio'}</button>}
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
            <tr className="border-b border-line"><th className="px-4 py-2 font-medium"></th><th className="px-4 py-2 text-right font-medium">Previsto</th><th className="px-4 py-2 text-right font-medium">Realizado</th><th className="px-4 py-2 text-right font-medium">Total</th></tr>
          </thead>
          <tbody>
            <tr className="border-b border-line bg-surface/60"><td className="px-4 py-2 font-medium">Saldo inicial do mês</td><td className="px-4 py-2 text-right text-ink-muted">—</td><td className="px-4 py-2 text-right text-ink-muted">—</td><td className={`px-4 py-2 text-right font-medium tabular-nums ${totalGeral.saldoInicial < 0 ? 'text-red-700' : ''}`}>{formatarMoeda(totalGeral.saldoInicial)}</td></tr>
            <Linha rotulo="Receitas" previsto={totalGeral.receitaPrevista} realizado={totalGeral.receitaRealizada} tom="receita" />
            <Linha rotulo="Despesas" previsto={-totalGeral.despesaPrevista} realizado={-totalGeral.despesaRealizada} tom="despesa" />
            <tr className="border-b border-line bg-surface/60"><td className="px-4 py-2 font-semibold">Resultado do período</td>
              <td className="px-4 py-2 text-right font-medium tabular-nums">{formatarMoeda(totalGeral.receitaPrevista - totalGeral.despesaPrevista)}</td>
              <td className={`px-4 py-2 text-right font-semibold tabular-nums ${totalGeral.receitaRealizada - totalGeral.despesaRealizada < 0 ? 'text-red-700' : 'text-green-700'}`}>{formatarMoeda(totalGeral.receitaRealizada - totalGeral.despesaRealizada)}</td>
              <td className="px-4 py-2 text-right font-semibold tabular-nums">{formatarMoeda((totalGeral.receitaPrevista + totalGeral.receitaRealizada) - (totalGeral.despesaPrevista + totalGeral.despesaRealizada))}</td>
            </tr>
            <tr><td className="px-4 py-2 font-semibold">Saldo final estimado do mês</td><td className="px-4 py-2" colSpan={2}></td>
              <td className={`px-4 py-2 text-right font-semibold tabular-nums ${saldoFinal < 0 ? 'text-red-700' : 'text-green-700'}`}>{formatarMoeda(saldoFinal)}</td>
            </tr>
          </tbody>
        </table>
      </div>
      {expandido && mostrarDetalhe && (
        <div className="overflow-x-auto border-t border-line">
          <table className="w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
              <tr className="border-b border-line"><th className="px-6 py-2 font-medium">Negócio</th><th className="px-6 py-2 text-right font-medium">Saldo inicial</th><th className="px-6 py-2 text-right font-medium">Receitas (real.)</th><th className="px-6 py-2 text-right font-medium">Despesas (real.)</th><th className="px-6 py-2 text-right font-medium">Resultado (real.)</th></tr>
            </thead>
            <tbody>
              {linhas.map((k) => { const g = grupos.get(k) ?? GRUPO_ZERO; const resultado = g.receitaRealizada - g.despesaRealizada; return (
                <tr key={k} className="border-b border-line last:border-0">
                  <td className="whitespace-nowrap px-6 py-2 font-medium">{nomeDe(k)}</td>
                  <td className="whitespace-nowrap px-6 py-2 text-right tabular-nums">{formatarMoeda(g.saldoInicial)}</td>
                  <td className="whitespace-nowrap px-6 py-2 text-right tabular-nums text-green-700">{formatarMoeda(g.receitaRealizada)}</td>
                  <td className="whitespace-nowrap px-6 py-2 text-right tabular-nums text-red-700">{formatarMoeda(g.despesaRealizada)}</td>
                  <td className={`whitespace-nowrap px-6 py-2 text-right font-medium tabular-nums ${resultado < 0 ? 'text-red-700' : 'text-green-700'}`}>{formatarMoeda(resultado)}</td>
                </tr>
              ) })}
            </tbody>
          </table>
        </div>
      )}
      <p className="border-t border-line px-6 py-2 text-xs text-ink-muted">Previsto = lançamentos ainda previstos no mês; Realizado = já efetivados. Cancelados não entram.</p>
    </Cartao>
  )
}
