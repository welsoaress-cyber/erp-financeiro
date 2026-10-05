import { CartaoRecolhivel } from '../../../core/ui/CartaoRecolhivel'
import { formatarMoeda } from '../../../core/formatos'
import type { LinhaVisaoPorNegocio } from '../api'

/** `previsto` é o que falta (ainda não efetivado); o total do mês é realizado + previsto. */
function Barra({ rotuloRealizado, realizado, previsto, tom }: { rotuloRealizado: string; realizado: number; previsto: number; tom: 'receita' | 'despesa' }) {
  const total = realizado + previsto
  const fracao = total > 0 ? Math.min(100, Math.round((realizado / total) * 100)) : 0
  const cor = tom === 'receita' ? 'bg-green-600' : 'bg-red-600'
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-baseline justify-between text-xs">
        <span className="font-semibold text-ink">{rotuloRealizado} — {formatarMoeda(realizado)} realizado</span>
        <span className="text-ink-muted">de {formatarMoeda(total)} previsto</span>
      </div>
      <div className="h-2 overflow-hidden rounded-full bg-surface">
        <div className={`h-full rounded-full ${cor}`} style={{ width: `${fracao}%` }} />
      </div>
    </div>
  )
}

/** Visão por negócio (0126): previsto × realizado, sempre negócio a negócio — nunca somado entre negócios. */
export function VisaoPorNegocio({ linhas }: { linhas: LinhaVisaoPorNegocio[] }) {
  if (linhas.length === 0) return null
  return (
    <CartaoRecolhivel
      id="visao-por-negocio"
      titulo={<h2 className="text-sm font-semibold">Visão por negócio</h2>}
      recolhidoPadrao={false}
    >
      <div className="flex flex-col gap-3 p-4">
        {linhas.map((l) => {
          const resultado = l.realizado.receitas - l.realizado.despesas
          return (
            <div key={l.chave} className="rounded-lg border border-line p-4">
              <div className="mb-3 flex items-center justify-between gap-2">
                <span className="text-sm font-semibold">{l.nome}</span>
                <span className={`text-sm font-semibold tabular-nums ${resultado < 0 ? 'text-red-700' : 'text-green-700'}`}>
                  Resultado: {resultado < 0 ? '− ' : '+ '}{formatarMoeda(Math.abs(resultado))}
                </span>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <Barra rotuloRealizado="Receitas" realizado={l.realizado.receitas} previsto={l.previsto.receitas} tom="receita" />
                <Barra rotuloRealizado="Despesas" realizado={l.realizado.despesas} previsto={l.previsto.despesas} tom="despesa" />
              </div>
            </div>
          )
        })}
      </div>
    </CartaoRecolhivel>
  )
}
