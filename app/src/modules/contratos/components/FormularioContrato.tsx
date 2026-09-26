import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { SelecaoBusca } from '../../../core/ui/SelecaoBusca'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { formatarMoeda, hojeISO } from '../../../core/formatos'
import type { Negocio } from '../../negocios/tipos'
import type { Pessoa } from '../../pessoas/tipos'
import type { Conta } from '../../contas/tipos'
import type { CentroCusto } from '../../centros_custo/tipos'
import { PERIODICIDADES, ROTULO_PESSOA_CONTRATO, ROTULO_TIPO_FINANCEIRO, type DadosNovoContrato, type Periodicidade, type Plano, type TipoFinanceiroContrato } from '../tipos'

interface Props {
  negocios: Negocio[]
  pessoas: Pessoa[]
  planos: Plano[]
  contas: Conta[]
  centros?: CentroCusto[]
  salvando: boolean
  erro: string | null
  aoSalvar: (d: DadosNovoContrato) => void
  aoCancelar: () => void
}

export function FormularioContrato({ negocios, pessoas, planos, contas, centros = [], salvando, erro, aoSalvar, aoCancelar }: Props) {
  const negociosAtivos = negocios.filter((n) => n.ativo)
  const [negocioId, setNegocioId] = useState(negociosAtivos.length === 1 ? negociosAtivos[0].id : '')
  const [tipoFinanceiro, setTipoFinanceiro] = useState<TipoFinanceiroContrato>('receita')
  const [pessoaId, setPessoaId] = useState('')
  const [planoId, setPlanoId] = useState('')
  const [valor, setValor] = useState('')
  const [periodicidade, setPeriodicidade] = useState<Periodicidade>('mensal')
  const [dataInicio, setDataInicio] = useState(hojeISO())
  const [dia, setDia] = useState('10')
  const [observacao, setObservacao] = useState('')
  const [contaId, setContaId] = useState('')
  const [cortesia, setCortesia] = useState(false)
  const [centroId, setCentroId] = useState('')
  const centrosDoNegocio = centros.filter((c) => c.negocio_id === negocioId && c.ativo) // sem cobrança: valor 0, faturamento pula
  const [erros, setErros] = useState<Record<string, string>>({})

  const planosDoNegocio = planos.filter((p) => p.negocio_id === negocioId && p.ativo)
  const planoSel = planos.find((p) => p.id === planoId)

  function escolherPlano(id: string) {
    setPlanoId(id)
    const p = planos.find((x) => x.id === id)
    if (p) { setValor(String(p.valor_tabela)); setPeriodicidade(p.periodicidade) }
  }

  function enviar(e: FormEvent) {
    e.preventDefault()
    const novos: Record<string, string> = {}
    const v = Number(valor.replace(',', '.'))
    const d = Number(dia)
    if (!negocioId) novos.negocio = 'Selecione o negócio.'
    if (!pessoaId) novos.pessoa = 'Selecione a pessoa.'
    if (!planoId) novos.plano = 'Selecione o plano.'
    if (!cortesia && (valor.trim() === '' || Number.isNaN(v) || v < 0)) novos.valor = 'Informe um valor válido.'
    if (!Number.isInteger(d) || d < 1 || d > 31) novos.dia = 'Dia entre 1 e 31.'
    if (!dataInicio) novos.data = 'Informe a data de início.'
    setErros(novos)
    if (Object.keys(novos).length) return
    aoSalvar({ negocio_id: negocioId, pessoa_id: pessoaId, plano_id: planoId, valor: cortesia ? 0 : Math.round(v * 100) / 100, periodicidade, data_inicio: dataInicio, dia_vencimento: d, observacao: observacao.trim() || null, faturar_desde: dataInicio, conta_id: contaId || null, tipo_financeiro: tipoFinanceiro, cortesia, centro_custo_id: tipoFinanceiro === 'despesa' ? (centroId || null) : null })
  }

  const erroCampo = (k: string) => erros[k] ? <p className="-mt-3 text-xs text-red-600">{erros[k]}</p> : null

  return (
    <form onSubmit={enviar} className="space-y-4" noValidate>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <Selecao rotulo="Negócio" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...negociosAtivos.map((n) => ({ valor: n.id, rotulo: n.nome }))]} value={negocioId} onChange={(e) => { setNegocioId(e.target.value); setPlanoId(''); setValor('') }} />
      {erroCampo('negocio')}
      <div role="radiogroup" aria-label="Tipo de contrato" className="grid grid-cols-2 gap-1 rounded-md border border-line p-1">
        {(Object.keys(ROTULO_TIPO_FINANCEIRO) as TipoFinanceiroContrato[]).map((t) => (
          <button key={t} type="button" role="radio" aria-checked={tipoFinanceiro === t} onClick={() => setTipoFinanceiro(t)}
            className={`rounded px-2 py-1.5 text-sm ${tipoFinanceiro === t ? 'bg-brand-600 text-white' : 'text-ink-muted hover:text-ink'}`}>{ROTULO_TIPO_FINANCEIRO[t]}</button>
        ))}
      </div>
      <SelecaoBusca rotulo={`Pessoa (${ROTULO_PESSOA_CONTRATO[tipoFinanceiro]})`} opcoes={pessoas.filter((p) => p.ativo).map((p) => ({ valor: p.id, rotulo: p.login_servidor ? `${p.nome} · ${p.login_servidor}` : p.nome }))} value={pessoaId} onChange={setPessoaId} placeholder="Digite o nome ou o login pra buscar…" erro={erros.pessoa} ajuda={`Se ainda não for ${ROTULO_PESSOA_CONTRATO[tipoFinanceiro].toLowerCase()} deste negócio, o vínculo é criado automaticamente.`} />
      <Selecao rotulo="Plano" opcoes={[{ valor: '', rotulo: negocioId ? (planosDoNegocio.length ? 'Selecione…' : 'Este negócio não tem planos ativos') : 'Escolha o negócio primeiro' }, ...planosDoNegocio.map((p) => ({ valor: p.id, rotulo: `${p.nome} · ${formatarMoeda(p.valor_tabela)}` }))]} value={planoId} onChange={(e) => escolherPlano(e.target.value)} disabled={!negocioId || planosDoNegocio.length === 0} />
      {erroCampo('plano')}
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Valor negociado (R$)" type="number" inputMode="decimal" step="0.01" min="0" value={cortesia ? '0' : valor} onChange={(e) => setValor(e.target.value)} disabled={cortesia} erro={erros.valor} placeholder={planoSel ? String(planoSel.valor_tabela) : ''} />
        <Selecao rotulo="Periodicidade" opcoes={PERIODICIDADES} value={periodicidade} onChange={(e) => setPeriodicidade(e.target.value as Periodicidade)} />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Início" type="date" value={dataInicio} onChange={(e) => { const v = e.target.value; setDataInicio(v); const d = Number(v.slice(8, 10)); if (d >= 1 && d <= 31) setDia(String(d)) }} erro={erros.data} />
        <Campo rotulo="Dia de vencimento" type="number" inputMode="numeric" min={1} max={31} value={dia} onChange={(e) => setDia(e.target.value)} erro={erros.dia} />
      </div>
      {tipoFinanceiro === 'receita' && (
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={cortesia} onChange={(e) => setCortesia(e.target.checked)} />
          <span>Cortesia (sem cobrança) — valor 0, o faturamento pula este contrato sem pendência.</span>
        </label>
      )}
      {tipoFinanceiro === 'despesa' && centrosDoNegocio.length > 0 && (
        <Selecao rotulo="Centro de custo (opcional)" opcoes={[{ valor: '', rotulo: 'Geral' }, ...centrosDoNegocio.map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={centroId} onChange={(e) => setCentroId(e.target.value)} ajuda="A despesa mensal deste fornecedor já nasce classificada neste centro." />
      )}
      <Selecao rotulo={tipoFinanceiro === 'despesa' ? 'Conta de pagamento' : 'Conta de recebimento'} opcoes={[{ valor: '', rotulo: 'Padrão do negócio' }, ...contas.filter((c) => c.ativo).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} ajuda={`Ao salvar, o primeiro lançamento ${tipoFinanceiro === 'despesa' ? 'de despesa (Contas a Pagar)' : 'de receita (Contas a Receber)'} já é gerado sozinho, sem precisar clicar em "Gerar faturamento agora" depois.`} />
      <AreaTexto rotulo="Observação (opcional)" rows={2} maxLength={500} value={observacao} onChange={(e) => setObservacao(e.target.value)} />
      <div className="flex justify-end gap-2 pt-2">
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando}>Voltar</Botao>
        <Botao type="submit" carregando={salvando}>Abrir contrato</Botao>
      </div>
    </form>
  )
}
