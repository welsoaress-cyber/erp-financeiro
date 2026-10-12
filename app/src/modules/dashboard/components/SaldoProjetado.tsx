import { useId, useMemo } from 'react'
import { Cartao } from '../../../core/ui/Cartao'
import { formatarMoedaOuOculto } from '../../../core/formatos'
import type { FluxoMensal } from '../../lancamentos/api'

const MES_ABREV = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']

interface Props {
  saldoAtual: number
  fluxos: FluxoMensal[]
  bate: (negocioId: string | null) => boolean
  oculto: boolean
}

/** Saldo projetado até dezembro: ponto de partida é o saldo atual das contas, e cada mês
 *  soma o fluxo previsto (receita − despesa) — lançamentos já gerados + projeção de contratos
 *  (vw/RPC projecao_saldo_mensal, 0137). Mostra se o ano fecha no azul ou no vermelho. */
export function SaldoProjetado({ saldoAtual, fluxos, bate, oculto }: Props) {
  const gradId = useId()
  const serie = useMemo(() => {
    const hoje = new Date()
    const meses: string[] = []
    for (let m = hoje.getMonth(); m <= 11; m++) meses.push(`${hoje.getFullYear()}-${String(m + 1).padStart(2, '0')}-01`)
    const fluxoPorMes = new Map<string, number>()
    for (const f of fluxos) {
      if (!bate(f.negocio_id)) continue
      fluxoPorMes.set(f.mes, (fluxoPorMes.get(f.mes) ?? 0) + (f.tipo === 'receita' ? f.valor : -f.valor))
    }
    let acumulado = saldoAtual
    return meses.map((mes) => {
      acumulado += fluxoPorMes.get(mes) ?? 0
      return { mes, idxMes: Number(mes.slice(5, 7)) - 1, saldo: acumulado }
    })
  }, [fluxos, bate, saldoAtual])

  const ultimo = serie[serie.length - 1]
  const anoAtual = new Date().getFullYear()

  if (serie.length < 2) {
    // dezembro: não há "resto do ano" pra desenhar — só o número final
    return (
      <Cartao className="p-5">
        <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">Saldo projetado · fim de {anoAtual}</p>
        <p className={`mt-2 text-2xl font-semibold tabular-nums ${ultimo && ultimo.saldo < 0 ? 'text-red-700' : 'text-green-700'}`}>
          {formatarMoedaOuOculto(ultimo?.saldo ?? saldoAtual, oculto)}
        </p>
      </Cartao>
    )
  }

  const W = 640, H = 220, PAD_X = 16, PAD_TOP = 36, PAD_BOTTOM = 28
  const valores = serie.map((p) => p.saldo)
  const min = Math.min(0, ...valores), max = Math.max(0, ...valores)
  const folga = (max - min) * 0.12 || 10
  const yMin = min - folga, yMax = max + folga
  const x = (i: number) => PAD_X + (i * (W - PAD_X * 2)) / (serie.length - 1)
  const y = (v: number) => PAD_TOP + (H - PAD_TOP - PAD_BOTTOM) * (1 - (v - yMin) / (yMax - yMin))
  const yZero = y(0)
  const zeroOffset = Math.max(0, Math.min(1, (yMax - 0) / (yMax - yMin))) * 100

  const linha = serie.map((p, i) => `${i === 0 ? 'M' : 'L'} ${x(i)} ${y(p.saldo)}`).join(' ')
  const area = `${linha} L ${x(serie.length - 1)} ${y(yMin < 0 ? 0 : yMin)} L ${x(0)} ${y(yMin < 0 ? 0 : yMin)} Z`

  return (
    <Cartao className="p-5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">Saldo projetado até dezembro de {anoAtual}</p>
        <p className={`text-lg font-semibold tabular-nums ${ultimo.saldo < 0 ? 'text-red-700' : 'text-green-700'}`}>{formatarMoedaOuOculto(ultimo.saldo, oculto)}</p>
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} className="mt-2 w-full" role="img" aria-label="Gráfico de saldo projetado mês a mês até dezembro">
        <defs>
          <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
            <stop offset={`${Math.max(0, zeroOffset - 2)}%`} stopColor="rgb(21 128 61)" stopOpacity="0.18" />
            <stop offset={`${Math.min(100, zeroOffset + 2)}%`} stopColor="rgb(185 28 28)" stopOpacity="0.18" />
          </linearGradient>
        </defs>
        {yMin < 0 && <line x1={PAD_X} y1={yZero} x2={W - PAD_X} y2={yZero} stroke="currentColor" className="text-line" strokeWidth="1" strokeDasharray="3 3" />}
        <path d={area} fill={`url(#${gradId})`} />
        <path d={linha} fill="none" stroke="rgb(21 128 61)" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />
        {serie.map((p, i) => (
          <g key={p.mes}>
            <circle cx={x(i)} cy={y(p.saldo)} r="4" className={p.saldo < 0 ? 'fill-red-700' : 'fill-green-700'} stroke="white" strokeWidth="1.5">
              <title>{`${MES_ABREV[p.idxMes]}/${anoAtual}: ${formatarMoedaOuOculto(p.saldo, oculto)}`}</title>
            </circle>
            {!oculto && (
              <text x={x(i)} y={y(p.saldo) - 10} textAnchor="middle" className="fill-ink text-[10px] tabular-nums">
                {formatarMoedaOuOculto(p.saldo, oculto).replace('R$', '').trim()}
              </text>
            )}
            <text x={x(i)} y={H - 8} textAnchor="middle" className="fill-ink-muted text-[10px]">{MES_ABREV[p.idxMes]}</text>
          </g>
        ))}
      </svg>
      <p className="text-xs text-ink-muted">Ponto de partida: saldo atual das contas. Depois, cada mês soma o previsto (lançamentos já gerados + projeção dos contratos) — supondo que tudo seja pago/recebido no prazo.</p>
    </Cartao>
  )
}
