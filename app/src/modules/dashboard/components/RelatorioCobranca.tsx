import { useState } from 'react'
import { CartaoRecolhivel } from '../../../core/ui/CartaoRecolhivel'
import { formatarMoeda, hojeISO } from '../../../core/formatos'
import { useCobranca } from '../api'
import { Link } from 'react-router'

type Periodo = 'dia' | 'semana' | 'mes'
const ROTULO: Record<Periodo, string> = { dia: 'Dia', semana: 'Semana', mes: 'Mês' }

function intervalo(p: Periodo): { inicio: string; fim: string } {
  const hoje = new Date()
  const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  if (p === 'dia') return { inicio: iso(hoje), fim: iso(hoje) }
  if (p === 'semana') {
    const dia = (hoje.getDay() + 6) % 7 // segunda = 0
    const ini = new Date(hoje); ini.setDate(hoje.getDate() - dia)
    const fim = new Date(ini); fim.setDate(ini.getDate() + 6)
    return { inicio: iso(ini), fim: iso(fim) }
  }
  const ini = new Date(hoje.getFullYear(), hoje.getMonth(), 1)
  const fim = new Date(hoje.getFullYear(), hoje.getMonth() + 1, 0)
  return { inicio: iso(ini), fim: iso(fim) }
}

/** Anel de progresso: fração do valor sobre o total dos três grupos. */
function Anel({ rotulo, quantidade, valor, fracao, cor }: { rotulo: string; quantidade: number; valor: number; fracao: number; cor: string }) {
  const r = 44
  const circ = 2 * Math.PI * r
  const arco = Math.max(0, Math.min(1, fracao)) * circ
  return (
    <div className="flex flex-col items-center gap-1 px-2 py-3">
      <p className="text-sm font-semibold">{rotulo}</p>
      <svg width="110" height="110" viewBox="0 0 110 110" role="img" aria-label={`${rotulo}: ${quantidade} cobranças, ${formatarMoeda(valor)}`}>
        <circle cx="55" cy="55" r={r} fill="none" stroke="var(--color-line, #e5e7eb)" strokeWidth="8" />
        {arco > 0 && (
          <circle cx="55" cy="55" r={r} fill="none" stroke={cor} strokeWidth="8" strokeLinecap="round"
            strokeDasharray={`${arco} ${circ - arco}`} transform="rotate(-90 55 55)" />
        )}
        <text x="55" y="55" textAnchor="middle" dominantBaseline="central" className="fill-current" fontSize="26" fontWeight="600">{quantidade}</text>
      </svg>
      <p className="text-sm font-medium tabular-nums">{formatarMoeda(valor)}</p>
    </div>
  )
}

/** Visão de cobrança estilo "relatório do dia": confirmadas × a receber × inadimplentes. */
export function RelatorioCobranca({ bate }: { bate: (negocioId: string | null) => boolean }) {
  const [periodo, setPeriodo] = useState<Periodo>('dia')
  const { inicio, fim } = intervalo(periodo)
  const cobranca = useCobranca(inicio, fim)
  const hoje = hojeISO()

  const efetivadas = (cobranca.data?.efetivadas ?? []).filter((l) => bate(l.negocio_id))
  const previstas = (cobranca.data?.previstas ?? []).filter((l) => bate(l.negocio_id))
  const aReceber = previstas.filter((l) => l.data_vencimento >= hoje && l.data_vencimento >= inicio)
  const vencidas = previstas.filter((l) => l.data_vencimento < hoje)
  const soma = (xs: { valor: number }[]) => xs.reduce((s, l) => s + l.valor, 0)
  const vC = soma(efetivadas); const vR = soma(aReceber); const vV = soma(vencidas)
  const total = vC + vR + vV

  return (
    <CartaoRecolhivel
      id="relatorio-cobranca"
      titulo={<h2 className="text-sm font-semibold">Cobrança do período</h2>}
      acao={<Link to="/financeiro/receber" className="shrink-0 text-xs font-medium text-brand-600 hover:underline">Abrir contas a receber</Link>}
    >
      <div className="px-6 pt-3">
        <div role="radiogroup" aria-label="Período" className="inline-flex gap-1 rounded-md border border-line p-1">
          {(['dia', 'semana', 'mes'] as Periodo[]).map((p) => (
            <button key={p} type="button" role="radio" aria-checked={periodo === p} onClick={() => setPeriodo(p)}
              className={`rounded px-3 py-1 text-sm ${periodo === p ? 'bg-brand-600 text-white' : 'text-ink-muted hover:text-ink'}`}>{ROTULO[p]}</button>
          ))}
        </div>
      </div>
      {cobranca.isPending ? (
        <p className="px-6 py-8 text-center text-sm text-ink-muted">Calculando…</p>
      ) : (
        <div className="grid grid-cols-1 divide-y divide-line sm:grid-cols-3 sm:divide-x sm:divide-y-0">
          <Anel rotulo="Confirmadas" quantidade={efetivadas.length} valor={vC} fracao={total > 0 ? vC / total : 0} cor="#15803d" />
          <Anel rotulo="A receber" quantidade={aReceber.length} valor={vR} fracao={total > 0 ? vR / total : 0} cor="#64748b" />
          <Anel rotulo="Inadimplentes" quantidade={vencidas.length} valor={vV} fracao={total > 0 ? vV / total : 0} cor="#dc2626" />
        </div>
      )}
      <p className="border-t border-line px-6 py-2 text-xs text-ink-muted">Confirmadas = receitas recebidas no período · A receber = previstas ainda no prazo · Inadimplentes = previstas já vencidas (acumulado).</p>
    </CartaoRecolhivel>
  )
}
