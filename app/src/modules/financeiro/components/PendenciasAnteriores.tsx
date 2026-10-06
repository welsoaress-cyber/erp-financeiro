import { CartaoRecolhivel } from '../../../core/ui/CartaoRecolhivel'
import { formatarData, formatarMoeda, hojeISO, mesAtualISO } from '../../../core/formatos'
import { useLancamentosVencidosAntes } from '../../lancamentos/api'

const diasAtraso = (vencimento: string) => Math.max(0, Math.round((Date.parse(hojeISO()) - Date.parse(vencimento)) / 86400000))

/** Previstos vencidos antes do mês corrente: fica visível não importa em qual mês o usuário esteja navegando. */
export function PendenciasAnteriores({ tipo, nomePessoa, aoAbrirAcao }: { tipo: 'receita' | 'despesa'; nomePessoa: Map<string, string>; aoAbrirAcao: (lancamentoId: string) => void }) {
  const receber = tipo === 'receita'
  const vencidos = useLancamentosVencidosAntes(tipo, mesAtualISO())
  if (!vencidos.data || vencidos.data.length === 0) return null
  const total = vencidos.data.reduce((s, l) => s + l.valor, 0)
  return (
    <div className="mb-4">
      <CartaoRecolhivel
        id={`pendencias-anteriores-${tipo}`}
        recolhidoPadrao={false}
        titulo={<h2 className="text-sm font-semibold text-red-800">{vencidos.data.length} pendência(s) de meses anteriores · {formatarMoeda(total)}</h2>}
      >
        <ul className="divide-y divide-line">
          {vencidos.data.slice(0, 8).map((l) => (
            <li key={l.id} className="flex flex-wrap items-center justify-between gap-2 px-6 py-2.5 text-sm">
              <span><b>{l.pessoa_id ? nomePessoa.get(l.pessoa_id) ?? '—' : '—'}</b> · {l.descricao} · vencido em {formatarData(l.data_vencimento)} (há {diasAtraso(l.data_vencimento)} dia(s)) · {formatarMoeda(l.valor)}</span>
              <button type="button" className="font-medium text-brand-700 underline" onClick={() => aoAbrirAcao(l.id)}>{receber ? 'Receber' : 'Pagar'}</button>
            </li>
          ))}
        </ul>
        {vencidos.data.length > 8 && <p className="px-6 py-2 text-xs text-ink-muted">+ {vencidos.data.length - 8} outro(s).</p>}
      </CartaoRecolhivel>
    </div>
  )
}
