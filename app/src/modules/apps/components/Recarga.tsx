import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { hojeISO } from '../../../core/formatos'
import type { Conta } from '../../contas/tipos'
import { useRecarregarCarteira } from '../api'
import { formatarSaldo, type ResumoCarteira } from '../tipos'

export function Recarga({ resumo, contas, aoConcluir }: { resumo: ResumoCarteira; contas: Conta[]; aoConcluir: () => void }) {
  const recarregar = useRecarregarCarteira()
  const [valor, setValor] = useState('')
  const [contaId, setContaId] = useState('')
  const [data, setData] = useState(hojeISO())
  const [observacao, setObservacao] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const v = Number(valor.replace(',', '.'))
  const unidades = resumo.tipo_saldo === 'credito' ? Math.round(v * (resumo.taxa_conversao ?? 0) * 100) / 100 : v
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (!(v > 0)) { setErro('Informe um valor maior que zero.'); return }
    if (!contaId) { setErro('Informe a conta de origem do dinheiro.'); return }
    setErro(null)
    recarregar.mutate({ negocioId: resumo.negocio_id, valorReais: Math.round(v * 100) / 100, contaOrigemId: contaId, data, observacao: observacao.trim() || null }, { onSuccess: aoConcluir })
  }
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || recarregar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(recarregar.error)}</Alerta>}
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Valor pago (R$)" type="number" inputMode="decimal" step="0.01" min="0.01" value={valor} onChange={(e) => setValor(e.target.value)} autoFocus />
        <Campo rotulo="Data" type="date" value={data} onChange={(e) => setData(e.target.value)} />
      </div>
      <Selecao rotulo="Conta de origem" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...contas.filter((c) => c.ativo && c.id !== resumo.conta_id).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} ajuda="O dinheiro sai desta conta e entra na conta da carteira (transferência efetivada)." />
      <Campo rotulo="Observação (opcional)" value={observacao} onChange={(e) => setObservacao(e.target.value)} maxLength={300} />
      {v > 0 && <p className="text-sm">Entra na carteira: <span className="font-semibold">{formatarSaldo(unidades, resumo.tipo_saldo)}</span></p>}
      <div className="flex justify-end gap-2"><Botao type="submit" carregando={recarregar.isPending}>Confirmar recarga</Botao></div>
    </form>
  )
}
