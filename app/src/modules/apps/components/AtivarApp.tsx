import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarMoeda, hojeISO } from '../../../core/formatos'
import type { Pessoa } from '../../pessoas/tipos'
import type { Plano } from '../../contratos/tipos'
import { useAtivarApp } from '../api'
import { FORMAS_PAGAMENTO, formatarValor, type AppCatalogo, type FormaPagamento, type ResumoCarteira } from '../tipos'

export function AtivarApp({ resumo, apps, planos, pessoas, aoConcluir }: { resumo: ResumoCarteira; apps: AppCatalogo[]; planos: Plano[]; pessoas: Pessoa[]; aoConcluir: () => void }) {
  const ativar = useAtivarApp()
  const [pessoaId, setPessoaId] = useState('')
  const [appId, setAppId] = useState(apps[0]?.id ?? '')
  const [forma, setForma] = useState<FormaPagamento>('dinheiro')
  const [valor, setValor] = useState('')
  const [data, setData] = useState(hojeISO())
  const [anuidade, setAnuidade] = useState('')
  const [observacao, setObservacao] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const app = apps.find((a) => a.id === appId)
  const plano = planos.find((p) => p.id === app?.plano_id)
  const v = Number(valor.replace(',', '.'))
  const saldoAtual = forma === 'credito' ? resumo.saldo_credito : resumo.saldo_dinheiro
  const saldoDepois = saldoAtual - (Number.isFinite(v) ? v : 0)
  const insuficiente = v > 0 && saldoAtual < v
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (!pessoaId) { setErro('Selecione o cliente.'); return }
    if (!app) { setErro('Selecione o app.'); return }
    if (!(v >= 0) || valor.trim() === '') { setErro('Informe o valor pago na ativação.'); return }
    if (saldoAtual < v) { setErro('Saldo insuficiente.'); return }
    const a = anuidade.trim() === '' ? null : Number(anuidade.replace(',', '.'))
    if (a !== null && (Number.isNaN(a) || a < 0)) { setErro('Anuidade inválida.'); return }
    setErro(null)
    ativar.mutate({ negocioId: resumo.negocio_id, pessoaId, appId: app.id, formaPagamento: forma, valor: Math.round(v * 100) / 100, data, anuidade: a, diaVencimento: null, observacao: observacao.trim() || null }, { onSuccess: aoConcluir })
  }
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || ativar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(ativar.error)}</Alerta>}
      <Selecao rotulo="Cliente" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...pessoas.filter((p) => p.ativo).map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={pessoaId} onChange={(e) => setPessoaId(e.target.value)} ajuda="Pessoa já cadastrada. Cadastre novas no menu Pessoas." />
      <Selecao rotulo="App" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...apps.filter((a) => a.ativo).map((a) => ({ valor: a.id, rotulo: a.nome }))]} value={appId} onChange={(e) => setAppId(e.target.value)} />
      <div className="grid grid-cols-2 gap-4">
        <Selecao rotulo="Pago com" opcoes={[...FORMAS_PAGAMENTO]} value={forma} onChange={(e) => setForma(e.target.value as FormaPagamento)} />
        <Campo rotulo={forma === 'credito' ? 'Créditos consumidos' : 'Valor pago (R$)'} type="number" inputMode="decimal" step="0.01" min="0" value={valor} onChange={(e) => setValor(e.target.value)} />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Data da ativação" type="date" value={data} onChange={(e) => setData(e.target.value)} />
        <Campo rotulo="Anuidade (R$)" type="number" inputMode="decimal" step="0.01" min="0" value={anuidade} onChange={(e) => setAnuidade(e.target.value)} placeholder={plano ? String(plano.valor_tabela) : ''} />
      </div>
      <Campo rotulo="Observação (opcional)" value={observacao} onChange={(e) => setObservacao(e.target.value)} maxLength={300} />
      {app && valor.trim() !== '' && (
        <div className={`rounded-md border p-3 text-sm ${insuficiente ? 'border-red-200 bg-red-50 text-red-800' : 'border-line bg-surface/60'}`}>
          <p>Consome <span className="font-semibold">{formatarValor(v, forma)}</span> · saldo depois: <span className="font-semibold">{formatarValor(saldoDepois, forma)}</span></p>
          <p className="mt-1 text-xs opacity-80">
            Abre um contrato anual de {formatarMoeda(anuidade.trim() ? Number(anuidade.replace(',', '.')) || 0 : plano?.valor_tabela ?? 0)} (receita prevista){forma === 'dinheiro' ? ' e lança a despesa do consumo na conta da carteira.' : '. Consumo em crédito não gera despesa (o custo já entrou na recarga).'}
          </p>
          {insuficiente && <p className="mt-1 font-medium">Saldo insuficiente. Faça uma recarga antes.</p>}
        </div>
      )}
      <div className="flex justify-end gap-2"><Botao type="submit" carregando={ativar.isPending} disabled={insuficiente || !app}>Confirmar ativação</Botao></div>
    </form>
  )
}
