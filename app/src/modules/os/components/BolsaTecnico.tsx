import { useMemo, useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarMoeda } from '../../../core/formatos'
import { useEstoqueItens } from '../../estoque/api'
import { fmtQtd } from '../../estoque/tipos'
import { useAbastecerTecnico, useBolsa, useDefinirMinimoBolsa, useDevolverTecnico, usePerdaTecnico, useTecnicoMovs } from '../api'
import { ROTULO_MOV_TECNICO, type Tecnico } from '../tipos'

/** Bolsa do técnico: saldo por item, abastecer/devolver/perda e histórico. */
export function BolsaTecnico({ tecnico, aoFechar }: { tecnico: Tecnico; aoFechar: () => void }) {
  const bolsa = useBolsa(tecnico.id)
  const movs = useTecnicoMovs(tecnico.id)
  const itens = useEstoqueItens()
  const abastecer = useAbastecerTecnico(); const devolver = useDevolverTecnico(); const perda = usePerdaTecnico(); const minimo = useDefinirMinimoBolsa()
  const [acao, setAcao] = useState<'abastecer' | 'devolver' | 'perda' | 'minimo'>('abastecer')
  const [itemId, setItemId] = useState('')
  const [qtd, setQtd] = useState('')
  const [motivo, setMotivo] = useState('')
  const [defeito, setDefeito] = useState(false)

  const itensNegocio = (itens.data ?? []).filter((i) => i.negocio_id === tecnico.negocio_id && i.ativo)
  const nomeItem = useMemo(() => new Map((itens.data ?? []).map((i) => [i.id, `${i.codigo} · ${i.nome}`])), [itens.data])
  const custoItem = useMemo(() => new Map((itens.data ?? []).map((i) => [i.id, i.valor_custo])), [itens.data])
  const linhaDe = (id: string) => (bolsa.data ?? []).find((b) => b.item_id === id)
  const erro = abastecer.error ?? devolver.error ?? perda.error ?? minimo.error
  const ocupado = abastecer.isPending || devolver.isPending || perda.isPending || minimo.isPending
  const v = Number(qtd.replace(',', '.'))

  function executar() {
    if (!itemId || !(v > 0) || (acao === 'perda' && motivo.trim().length < 3)) return
    const limpar = { onSuccess: () => { setQtd(''); setMotivo('') } }
    if (acao === 'abastecer') abastecer.mutate({ p_tecnico_id: tecnico.id, p_item_id: itemId, p_quantidade: v }, limpar)
    if (acao === 'devolver') devolver.mutate({ p_tecnico_id: tecnico.id, p_item_id: itemId, p_quantidade: v }, limpar)
    if (acao === 'perda') perda.mutate({ p_tecnico_id: tecnico.id, p_item_id: itemId, p_quantidade: v, p_avaria: false, p_motivo: motivo.trim(), p_defeito_fabrica: defeito }, limpar)
    if (acao === 'minimo') minimo.mutate({ tecnico_id: tecnico.id, item_id: itemId, quantidade_minima: v, id: linhaDe(itemId)?.id }, limpar)
  }

  return (
    <div className="space-y-4">
      {erro != null && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}
      <div className="flex flex-wrap items-end gap-2 rounded-md border border-line p-3">
        <Selecao rotulo="Ação" opcoes={[{ valor: 'abastecer', rotulo: 'Abastecer (do central)' }, { valor: 'devolver', rotulo: 'Devolver (ao central)' }, { valor: 'perda', rotulo: 'Perda / avaria' }, { valor: 'minimo', rotulo: 'Definir mínimo' }]} value={acao} onChange={(e) => setAcao(e.target.value as typeof acao)} />
        <div className="min-w-44 flex-1"><Selecao rotulo="Item" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...itensNegocio.map((i) => ({ valor: i.id, rotulo: `${i.codigo} · ${i.nome}` }))]} value={itemId} onChange={(e) => setItemId(e.target.value)} /></div>
        <Campo rotulo={acao === 'minimo' ? 'Qtd. mínima' : 'Quantidade'} type="number" step="0.01" min="0" value={qtd} onChange={(e) => setQtd(e.target.value)} className="w-28" />
        {acao === 'perda' && (
          <>
            <div className="min-w-40 flex-1"><Campo rotulo="Motivo (obrigatório)" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={300} /></div>
            <label className="flex items-center gap-1 pb-2.5 text-sm"><input type="checkbox" checked={defeito} onChange={(e) => setDefeito(e.target.checked)} className="size-4 accent-brand-600" />Defeito de fábrica</label>
          </>
        )}
        <Botao onClick={executar} carregando={ocupado} disabled={!itemId || !(v > 0) || (acao === 'perda' && motivo.trim().length < 3)}>Confirmar</Botao>
      </div>

      <div className="overflow-x-auto rounded-md border border-line">
        <table className="w-full text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Item</th><th className="px-4 py-2 text-right font-medium">Na bolsa</th><th className="px-4 py-2 text-right font-medium">Mínimo</th><th className="px-4 py-2 text-right font-medium">Valor</th><th className="px-4 py-2 font-medium">Situação</th></tr></thead>
          <tbody>
            {(bolsa.data ?? []).length === 0 && <tr><td colSpan={5} className="px-4 py-8 text-center text-ink-muted">Bolsa vazia. Abasteça a partir do estoque central.</td></tr>}
            {(bolsa.data ?? []).map((b) => (
              <tr key={b.id} className="border-b border-line last:border-0">
                <td className="px-4 py-2">{nomeItem.get(b.item_id) ?? '—'}</td>
                <td className={`px-4 py-2 text-right tabular-nums ${b.quantidade < 0 ? 'font-semibold text-red-700' : ''}`}>{fmtQtd(b.quantidade)}</td>
                <td className="px-4 py-2 text-right tabular-nums">{fmtQtd(b.quantidade_minima)}</td>
                <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(Math.max(b.quantidade, 0) * (custoItem.get(b.item_id) ?? 0))}</td>
                <td className="px-4 py-2">{b.quantidade < 0 ? <Distintivo tom="alerta">Negativo — repor</Distintivo> : b.quantidade < b.quantidade_minima ? <Distintivo tom="alerta">Abaixo do mínimo</Distintivo> : <Distintivo tom="ok">OK</Distintivo>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="rounded-md border border-line p-3">
        <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-ink-muted">Últimas movimentações</p>
        <ul className="space-y-1 text-xs text-ink-muted">
          {(movs.data ?? []).slice(0, 15).map((m) => (
            <li key={m.id}>
              <span className="tabular-nums">{new Date(m.criado_em).toLocaleDateString('pt-BR')}</span> · <b>{ROTULO_MOV_TECNICO[m.tipo]}</b> · {nomeItem.get(m.item_id) ?? '—'} · {fmtQtd(m.quantidade)} · {formatarMoeda(m.valor_total)}
              {m.motivo ? ` — ${m.motivo}` : ''}{m.defeito_fabrica ? ' (defeito de fábrica)' : ''}
            </li>
          ))}
        </ul>
      </div>
      <div className="flex justify-end"><Botao variante="secundario" onClick={aoFechar}>Fechar</Botao></div>
    </div>
  )
}
