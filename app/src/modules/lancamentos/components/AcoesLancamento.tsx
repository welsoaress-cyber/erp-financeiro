import { useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { formatarData, hojeISO } from '../../../core/formatos'
import type { Lancamento } from '../tipos'

interface Props {
  lancamento: Lancamento
  ocupado: boolean
  erro: string | null
  aoEfetivar: (data: string) => void
  aoCancelarLancamento: (motivo: string) => void
  aoExcluir: () => void
  aoProjetar?: (meses: number) => void
}

/** Ações de estado de um lançamento existente: efetivar, cancelar (com motivo), excluir (só previsto) e projetar (recorrentes). */
export function AcoesLancamento({ lancamento, ocupado, erro, aoEfetivar, aoCancelarLancamento, aoExcluir, aoProjetar }: Props) {
  const [modo, setModo] = useState<'nenhum' | 'efetivar' | 'cancelar' | 'excluir' | 'projetar'>('nenhum')
  const [dataEf, setDataEf] = useState(hojeISO())
  const [motivo, setMotivo] = useState('')
  const [meses, setMeses] = useState('6')

  if (lancamento.status === 'cancelado') {
    return (
      <Alerta tipo="info" titulo={`Cancelado em ${formatarData(lancamento.cancelado_em!.slice(0, 10))}`}>
        {lancamento.motivo_cancelamento ?? 'Sem motivo informado.'} Lançamentos cancelados não podem ser alterados.
      </Alerta>
    )
  }

  const fixa = lancamento.tipo_recorrencia === 'fixa'

  return (
    <div className="space-y-3 border-t border-line pt-4">
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      {modo === 'nenhum' && (
        <div className="flex flex-wrap gap-2">
          {lancamento.status === 'previsto' && <Botao type="button" onClick={() => setModo('efetivar')}>{lancamento.tipo === 'receita' ? 'Marcar como recebido' : 'Marcar como pago'}</Botao>}
          {lancamento.recorrente && aoProjetar && fixa && (
            <Botao type="button" variante="secundario" onClick={() => aoProjetar(60)} carregando={ocupado}>Gerar próximas ocorrências</Botao>
          )}
          {lancamento.recorrente && aoProjetar && !fixa && <Botao type="button" variante="secundario" onClick={() => setModo('projetar')}>Projetar meses futuros</Botao>}
          <Botao type="button" variante="secundario" onClick={() => setModo('cancelar')}>Cancelar lançamento</Botao>
          {lancamento.status === 'previsto' && <Botao type="button" variante="perigo" onClick={() => setModo('excluir')}>Excluir</Botao>}
        </div>
      )}
      {modo === 'efetivar' && (
        <div className="flex items-end gap-2">
          <Campo rotulo="Data de efetivação" type="date" value={dataEf} onChange={(e) => setDataEf(e.target.value)} />
          <Botao type="button" onClick={() => aoEfetivar(dataEf)} carregando={ocupado}>Confirmar</Botao>
          <Botao type="button" variante="secundario" onClick={() => setModo('nenhum')}>Voltar</Botao>
        </div>
      )}
      {modo === 'projetar' && aoProjetar && !fixa && (
        <div className="space-y-2">
          <p className="text-sm text-ink-muted">Gera as próximas ocorrências já como previstas, sem precisar pagar as anteriores primeiro. Só valores, datas e a conta/categoria de hoje — nada é cobrado até você efetivar cada uma.</p>
          <div className="flex items-end gap-2">
            <Campo rotulo="Meses à frente" type="number" inputMode="numeric" min={1} max={60} value={meses} onChange={(e) => setMeses(e.target.value)} />
            <Botao type="button" onClick={() => aoProjetar(Number(meses))} carregando={ocupado} disabled={!Number.isInteger(Number(meses)) || Number(meses) < 1}>Gerar</Botao>
            <Botao type="button" variante="secundario" onClick={() => setModo('nenhum')}>Voltar</Botao>
          </div>
        </div>
      )}
      {modo === 'cancelar' && (
        <div className="space-y-2">
          <Campo rotulo="Motivo do cancelamento (opcional)" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={200} />
          <p className="text-xs text-ink-muted">O lançamento fica no histórico como cancelado e deixa de afetar o saldo. Não pode ser desfeito.</p>
          {lancamento.recorrente && lancamento.status === 'previsto' && <p className="text-xs text-amber-800">Parcela prevista de uma recorrência: cancelar interrompe a recorrência (nenhuma parcela seguinte será gerada).</p>}
          {lancamento.recorrente && lancamento.status === 'efetivado' && <p className="text-xs text-ink-muted">Parcela efetivada de uma recorrência: cancelar só estorna esta parcela; a próxima já gerada continua.</p>}
          <div className="flex gap-2">
            <Botao type="button" variante="perigo" onClick={() => aoCancelarLancamento(motivo)} carregando={ocupado}>Confirmar cancelamento</Botao>
            <Botao type="button" variante="secundario" onClick={() => setModo('nenhum')}>Voltar</Botao>
          </div>
        </div>
      )}
      {modo === 'excluir' && (
        <div className="space-y-2">
          <p className="text-sm">Excluir definitivamente este lançamento previsto?</p>
          {lancamento.recorrente && <p className="text-xs text-amber-800">Excluir esta parcela interrompe a recorrência.</p>}
          <div className="flex gap-2">
            <Botao type="button" variante="perigo" onClick={aoExcluir} carregando={ocupado}>Excluir</Botao>
            <Botao type="button" variante="secundario" onClick={() => setModo('nenhum')}>Voltar</Botao>
          </div>
        </div>
      )}
    </div>
  )
}
