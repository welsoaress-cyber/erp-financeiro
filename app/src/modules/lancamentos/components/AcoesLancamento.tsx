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
}

/** Ações de estado de um lançamento existente: efetivar, cancelar (com motivo) e excluir (só previsto). */
export function AcoesLancamento({ lancamento, ocupado, erro, aoEfetivar, aoCancelarLancamento, aoExcluir }: Props) {
  const [modo, setModo] = useState<'nenhum' | 'efetivar' | 'cancelar' | 'excluir'>('nenhum')
  const [dataEf, setDataEf] = useState(hojeISO())
  const [motivo, setMotivo] = useState('')

  if (lancamento.status === 'cancelado') {
    return (
      <Alerta tipo="info" titulo={`Cancelado em ${formatarData(lancamento.cancelado_em!.slice(0, 10))}`}>
        {lancamento.motivo_cancelamento ?? 'Sem motivo informado.'} Lançamentos cancelados não podem ser alterados.
      </Alerta>
    )
  }

  return (
    <div className="space-y-3 border-t border-line pt-4">
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      {modo === 'nenhum' && (
        <div className="flex flex-wrap gap-2">
          {lancamento.status === 'previsto' && <Botao type="button" onClick={() => setModo('efetivar')}>{lancamento.tipo === 'receita' ? 'Marcar como recebido' : 'Marcar como pago'}</Botao>}
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
