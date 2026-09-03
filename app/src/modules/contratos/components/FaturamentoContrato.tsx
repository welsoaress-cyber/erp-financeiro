import { useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMes, formatarMoeda } from '../../../core/formatos'
import type { Conta } from '../../contas/tipos'
import { useAtualizarContrato, useFaturamentos } from '../api'
import type { Contrato } from '../tipos'

const TOM: Record<string, 'ok' | 'alerta' | 'neutro'> = { efetivado: 'ok', previsto: 'alerta', cancelado: 'neutro' }
const ROTULO: Record<string, string> = { efetivado: 'Recebido', previsto: 'Previsto', cancelado: 'Cancelado' }

/** Configuração de faturamento do contrato e histórico das competências geradas. */
export function FaturamentoContrato({ contrato, contas }: { contrato: Contrato; contas: Conta[] }) {
  const atualizar = useAtualizarContrato()
  const faturamentos = useFaturamentos()
  const [automatico, setAutomatico] = useState(contrato.faturamento_automatico)
  const [desde, setDesde] = useState(contrato.faturar_desde ?? contrato.data_inicio)
  const [contaId, setContaId] = useState(contrato.conta_id ?? '')
  const meus = (faturamentos.data ?? []).filter((f) => f.contrato_id === contrato.id).sort((a, b) => b.competencia.localeCompare(a.competencia))
  const encerrado = contrato.status === 'encerrado'
  const alterado = automatico !== contrato.faturamento_automatico || desde !== (contrato.faturar_desde ?? contrato.data_inicio) || (contaId || null) !== contrato.conta_id

  return (
    <div className="space-y-3 border-t border-line pt-4">
      <h3 className="text-sm font-semibold">Faturamento recorrente</h3>
      {atualizar.error && <Alerta tipo="erro">{mensagemDeErro(atualizar.error)}</Alerta>}
      {!encerrado && (
        <>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={automatico} onChange={(e) => setAutomatico(e.target.checked)} className="size-4 accent-brand-600" />
            Gerar cobranças automaticamente
          </label>
          <div className="grid grid-cols-2 gap-4">
            <Campo rotulo="Faturar a partir de" type="date" value={desde} onChange={(e) => setDesde(e.target.value)} disabled={!automatico} />
            <Selecao rotulo="Conta de recebimento" opcoes={[{ valor: '', rotulo: 'Padrão do negócio' }, ...contas.filter((c) => c.ativo || c.id === contrato.conta_id).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} disabled={!automatico} />
          </div>
          {alterado && (
            <div className="flex justify-end">
              <Botao type="button" variante="secundario" carregando={atualizar.isPending} onClick={() => atualizar.mutate({ id: contrato.id, faturamento_automatico: automatico, faturar_desde: desde, conta_id: contaId || null })}>Salvar faturamento</Botao>
            </div>
          )}
        </>
      )}
      {meus.length === 0
        ? <p className="text-sm text-ink-muted">Nenhuma cobrança gerada ainda. Use "Gerar faturamento agora" na lista de contratos.</p>
        : (
          <ul className="max-h-48 divide-y divide-line overflow-y-auto rounded-md border border-line">
            {meus.map((f) => (
              <li key={f.id} className="flex items-center justify-between gap-3 px-3 py-2 text-sm">
                <span><span className="font-medium">{formatarMes(f.competencia)}</span> <span className="text-ink-muted">· vence {formatarData(f.data_vencimento)}</span></span>
                <span className="flex items-center gap-2 tabular-nums">{formatarMoeda(f.valor)} <Distintivo tom={TOM[f.status_lancamento] ?? 'neutro'}>{ROTULO[f.status_lancamento] ?? f.status_lancamento}</Distintivo></span>
              </li>
            ))}
          </ul>
        )}
    </div>
  )
}
