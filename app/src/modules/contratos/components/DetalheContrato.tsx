import { useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Distintivo } from '../../../core/ui/Distintivo'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda, hojeISO } from '../../../core/formatos'
import { useAtualizarContrato } from '../api'
import { Selecao } from '../../../core/ui/Selecao'
import { codigoContrato, PERIODICIDADES, ROTULO_PERIODICIDADE, ROTULO_STATUS_CONTRATO, type Contrato, type Periodicidade, type ResultadoContrato } from '../tipos'
import { FaturamentoContrato } from './FaturamentoContrato'
import type { Conta } from '../../contas/tipos'

interface Props {
  contrato: Contrato
  nomes: { negocio: string; pessoa: string; plano: string }
  resultado?: ResultadoContrato
  contas: Conta[]
  aoFechar: () => void
}

const TOM: Record<Contrato['status'], 'ok' | 'alerta' | 'neutro'> = { ativo: 'ok', suspenso: 'alerta', encerrado: 'neutro' }

/** Detalhe do contrato: dados, rentabilidade, edição de valor/vencimento e ciclo de vida. */
export function DetalheContrato({ contrato, nomes, resultado, contas, aoFechar }: Props) {
  const atualizar = useAtualizarContrato()
  const encerrado = contrato.status === 'encerrado'
  const [valor, setValor] = useState(String(contrato.valor))
  const [dia, setDia] = useState(String(contrato.dia_vencimento))
  const [periodicidade, setPeriodicidade] = useState<Periodicidade>(contrato.periodicidade)
  const [observacao, setObservacao] = useState(contrato.observacao ?? '')
  const [modo, setModo] = useState<'nenhum' | 'encerrar'>('nenhum')
  // Encerramento nunca pode ser antes do início do contrato (check do banco)
  const dataFimMinima = contrato.data_inicio > hojeISO() ? contrato.data_inicio : hojeISO()
  const [dataFim, setDataFim] = useState(dataFimMinima)

  function salvar() {
    const v = Number(valor.replace(',', '.')); const d = Number(dia)
    if (Number.isNaN(v) || v < 0 || !Number.isInteger(d) || d < 1 || d > 31) return
    atualizar.mutate({ id: contrato.id, valor: Math.round(v * 100) / 100, dia_vencimento: d, periodicidade, observacao: observacao.trim() || null }, { onSuccess: aoFechar })
  }

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 text-sm">
        <div>
          <p className="font-medium">{nomes.pessoa}</p>
          <p className="text-ink-muted">{nomes.negocio} · {nomes.plano} · {ROTULO_PERIODICIDADE[contrato.periodicidade]}</p>
          <p className="text-xs text-ink-muted">Início {formatarData(contrato.data_inicio)}{contrato.data_fim ? ` · Fim ${formatarData(contrato.data_fim)}` : ''}</p>
        </div>
        <Distintivo tom={TOM[contrato.status]}>{ROTULO_STATUS_CONTRATO[contrato.status]}</Distintivo>
      </div>

      <div className="grid grid-cols-3 gap-2 rounded-md border border-line bg-surface/60 p-3 text-center">
        <div><p className="text-xs uppercase tracking-wide text-ink-muted">Receitas</p><p className="font-semibold tabular-nums text-green-700">{formatarMoeda(resultado?.receitas ?? 0)}</p></div>
        <div><p className="text-xs uppercase tracking-wide text-ink-muted">Despesas</p><p className="font-semibold tabular-nums text-red-700">{formatarMoeda(resultado?.despesas ?? 0)}</p></div>
        <div><p className="text-xs uppercase tracking-wide text-ink-muted">Resultado</p><p className={`font-semibold tabular-nums ${(resultado?.resultado ?? 0) < 0 ? 'text-red-700' : 'text-green-700'}`}>{formatarMoeda(resultado?.resultado ?? 0)}</p></div>
        <p className="col-span-3 text-xs text-ink-muted">{resultado?.lancamentos ?? 0} lançamento(s) efetivado(s) vinculado(s) a este contrato{resultado?.ultimo_lancamento ? ` · último em ${formatarData(resultado.ultimo_lancamento)}` : ''}.</p>
      </div>

      {atualizar.error && <Alerta tipo="erro">{mensagemDeErro(atualizar.error)}</Alerta>}

      {encerrado ? (
        <Alerta tipo="info">Contrato encerrado. Não pode ser alterado; o histórico permanece na rentabilidade.</Alerta>
      ) : (
        <>
          <div className="grid grid-cols-3 gap-4">
            <Campo rotulo="Valor negociado (R$)" type="number" inputMode="decimal" step="0.01" min="0" value={valor} onChange={(e) => setValor(e.target.value)} />
            <Campo rotulo="Dia de vencimento" type="number" min={1} max={31} value={dia} onChange={(e) => setDia(e.target.value)} />
            <Selecao rotulo="Periodicidade" opcoes={PERIODICIDADES} value={periodicidade} onChange={(e) => setPeriodicidade(e.target.value as Periodicidade)} />
          </div>
          <AreaTexto rotulo="Observação (opcional)" rows={2} maxLength={500} value={observacao} onChange={(e) => setObservacao(e.target.value)} />
          <div className="flex flex-wrap justify-between gap-2 border-t border-line pt-3">
            <div className="flex gap-2">
              {contrato.status === 'ativo' && <Botao type="button" variante="secundario" onClick={() => atualizar.mutate({ id: contrato.id, status: 'suspenso' }, { onSuccess: aoFechar })} carregando={atualizar.isPending}>Suspender</Botao>}
              {contrato.status === 'suspenso' && <Botao type="button" variante="secundario" onClick={() => atualizar.mutate({ id: contrato.id, status: 'ativo' }, { onSuccess: aoFechar })} carregando={atualizar.isPending}>Reativar</Botao>}
              {modo === 'nenhum' && <Botao type="button" variante="perigo" onClick={() => setModo('encerrar')}>Encerrar</Botao>}
            </div>
            <Botao type="button" onClick={salvar} carregando={atualizar.isPending}>Salvar alterações</Botao>
          </div>
          {modo === 'encerrar' && (
            <div className="space-y-2 rounded-md border border-red-200 bg-red-50 p-3">
              {dataFim < contrato.data_inicio && <p className="text-xs text-red-800">A data de encerramento não pode ser anterior ao início do contrato ({formatarData(contrato.data_inicio)}).</p>}
              <div className="flex items-end gap-2">
                <Campo rotulo="Data de encerramento" type="date" min={contrato.data_inicio} value={dataFim} onChange={(e) => setDataFim(e.target.value)} />
                <Botao type="button" variante="perigo" onClick={() => atualizar.mutate({ id: contrato.id, status: 'encerrado', data_fim: dataFim }, { onSuccess: aoFechar })} carregando={atualizar.isPending} disabled={dataFim < contrato.data_inicio}>Confirmar encerramento</Botao>
                <Botao type="button" variante="secundario" onClick={() => setModo('nenhum')}>Voltar</Botao>
              </div>
            </div>
          )}
        </>
      )}
      <FaturamentoContrato contrato={contrato} contas={contas} />
      <p className="text-xs text-ink-muted">Contrato {codigoContrato(contrato)} · Pessoa, negócio e plano não mudam depois de aberto: encerre e abra outro.</p>
    </div>
  )
}
