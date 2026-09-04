import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { hojeISO } from '../../../core/formatos'
import type { Conta } from '../../contas/tipos'
import { useRecarregarCarteira } from '../api'
import { FORMAS_PAGAMENTO, formatarValor, type FormaPagamento, type ResumoCarteira } from '../tipos'

export function Recarga({ resumo, contas, aoConcluir }: { resumo: ResumoCarteira; contas: Conta[]; aoConcluir: () => void }) {
  const recarregar = useRecarregarCarteira()
  const [forma, setForma] = useState<FormaPagamento>('dinheiro')
  const [valorReais, setValorReais] = useState('')
  const [creditos, setCreditos] = useState('')
  const [contaId, setContaId] = useState('')
  const [data, setData] = useState(hojeISO())
  const [observacao, setObservacao] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const vReais = Number(valorReais.replace(',', '.'))
  const vCreditos = Number(creditos.replace(',', '.'))
  const unidades = forma === 'credito' ? vCreditos : vReais
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (!(vReais > 0)) { setErro('Informe o valor pago (PIX) maior que zero.'); return }
    if (forma === 'credito' && !(vCreditos > 0)) { setErro('Informe quantos créditos a recarga trouxe.'); return }
    if (!contaId) { setErro('Informe a conta de origem do dinheiro.'); return }
    setErro(null)
    recarregar.mutate({
      negocioId: resumo.negocio_id, formaPagamento: forma, valorReais: Math.round(vReais * 100) / 100,
      unidades: forma === 'credito' ? Math.round(vCreditos * 100) / 100 : null, contaOrigemId: contaId, data, observacao: observacao.trim() || null,
    }, { onSuccess: aoConcluir })
  }
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || recarregar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(recarregar.error)}</Alerta>}
      <Selecao rotulo="Forma de pagamento" opcoes={[...FORMAS_PAGAMENTO]} value={forma} onChange={(e) => setForma(e.target.value as FormaPagamento)} ajuda="Qual saldo esta recarga vai abastecer." />
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Valor pago via PIX (R$)" type="number" inputMode="decimal" step="0.01" min="0.01" value={valorReais} onChange={(e) => setValorReais(e.target.value)} autoFocus />
        <Campo rotulo="Data" type="date" value={data} onChange={(e) => setData(e.target.value)} />
      </div>
      {forma === 'credito' && (
        <div className="space-y-1">
          <Campo rotulo="Créditos recebidos" type="number" inputMode="decimal" step="0.01" min="0.01" value={creditos} onChange={(e) => setCreditos(e.target.value)} />
          <p className="text-xs text-ink-muted">Quantos créditos a plataforma creditou por esse PIX (sem taxa fixa).</p>
        </div>
      )}
      <Selecao rotulo="Conta de origem" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...contas.filter((c) => c.ativo && c.id !== resumo.conta_id).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} ajuda="O dinheiro sai desta conta e entra na conta da carteira (transferência efetivada)." />
      <Campo rotulo="Observação (opcional)" value={observacao} onChange={(e) => setObservacao(e.target.value)} maxLength={300} />
      {unidades > 0 && <p className="text-sm">Entra na carteira: <span className="font-semibold">{formatarValor(unidades, forma)}</span></p>}
      <div className="flex justify-end gap-2"><Botao type="submit" carregando={recarregar.isPending}>Confirmar recarga</Botao></div>
    </form>
  )
}
