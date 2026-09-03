import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { formatarMoeda, hojeISO } from '../../../core/formatos'
import type { Negocio } from '../../negocios/tipos'
import type { Pessoa } from '../../pessoas/tipos'
import type { Conta } from '../../contas/tipos'
import { PERIODICIDADES, type DadosNovoContrato, type Periodicidade, type Plano } from '../tipos'

interface Props {
  negocios: Negocio[]
  pessoas: Pessoa[]
  planos: Plano[]
  contas: Conta[]
  salvando: boolean
  erro: string | null
  aoSalvar: (d: DadosNovoContrato) => void
  aoCancelar: () => void
}

export function FormularioContrato({ negocios, pessoas, planos, contas, salvando, erro, aoSalvar, aoCancelar }: Props) {
  const negociosAtivos = negocios.filter((n) => n.ativo)
  const [negocioId, setNegocioId] = useState(negociosAtivos.length === 1 ? negociosAtivos[0].id : '')
  const [pessoaId, setPessoaId] = useState('')
  const [planoId, setPlanoId] = useState('')
  const [valor, setValor] = useState('')
  const [periodicidade, setPeriodicidade] = useState<Periodicidade>('mensal')
  const [dataInicio, setDataInicio] = useState(hojeISO())
  const [dia, setDia] = useState('10')
  const [observacao, setObservacao] = useState('')
  const [contaId, setContaId] = useState('')
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
    if (valor.trim() === '' || Number.isNaN(v) || v < 0) novos.valor = 'Informe um valor válido.'
    if (!Number.isInteger(d) || d < 1 || d > 31) novos.dia = 'Dia entre 1 e 31.'
    if (!dataInicio) novos.data = 'Informe a data de início.'
    setErros(novos)
    if (Object.keys(novos).length) return
    aoSalvar({ negocio_id: negocioId, pessoa_id: pessoaId, plano_id: planoId, valor: Math.round(v * 100) / 100, periodicidade, data_inicio: dataInicio, dia_vencimento: d, observacao: observacao.trim() || null, faturar_desde: dataInicio, conta_id: contaId || null })
  }

  const erroCampo = (k: string) => erros[k] ? <p className="-mt-3 text-xs text-red-600">{erros[k]}</p> : null

  return (
    <form onSubmit={enviar} className="space-y-4" noValidate>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <Selecao rotulo="Negócio" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...negociosAtivos.map((n) => ({ valor: n.id, rotulo: n.nome }))]} value={negocioId} onChange={(e) => { setNegocioId(e.target.value); setPlanoId(''); setValor('') }} />
      {erroCampo('negocio')}
      <Selecao rotulo="Pessoa (cliente)" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...pessoas.filter((p) => p.ativo).map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={pessoaId} onChange={(e) => setPessoaId(e.target.value)} ajuda="Se ainda não for cliente deste negócio, o vínculo é criado automaticamente." />
      {erroCampo('pessoa')}
      <Selecao rotulo="Plano" opcoes={[{ valor: '', rotulo: negocioId ? (planosDoNegocio.length ? 'Selecione…' : 'Este negócio não tem planos ativos') : 'Escolha o negócio primeiro' }, ...planosDoNegocio.map((p) => ({ valor: p.id, rotulo: `${p.nome} · ${formatarMoeda(p.valor_tabela)}` }))]} value={planoId} onChange={(e) => escolherPlano(e.target.value)} disabled={!negocioId || planosDoNegocio.length === 0} />
      {erroCampo('plano')}
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Valor negociado (R$)" type="number" inputMode="decimal" step="0.01" min="0" value={valor} onChange={(e) => setValor(e.target.value)} erro={erros.valor} placeholder={planoSel ? String(planoSel.valor_tabela) : ''} />
        <Selecao rotulo="Periodicidade" opcoes={PERIODICIDADES} value={periodicidade} onChange={(e) => setPeriodicidade(e.target.value as Periodicidade)} />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Início" type="date" value={dataInicio} onChange={(e) => setDataInicio(e.target.value)} erro={erros.data} />
        <Campo rotulo="Dia de vencimento" type="number" inputMode="numeric" min={1} max={31} value={dia} onChange={(e) => setDia(e.target.value)} erro={erros.dia} />
      </div>
      <Selecao rotulo="Conta de recebimento" opcoes={[{ valor: '', rotulo: 'Padrão do negócio' }, ...contas.filter((c) => c.ativo).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} ajuda="Onde as cobranças geradas automaticamente entram. As cobranças começam na data de início." />
      <AreaTexto rotulo="Observação (opcional)" rows={2} maxLength={500} value={observacao} onChange={(e) => setObservacao(e.target.value)} />
      <div className="flex justify-end gap-2 pt-2">
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando}>Voltar</Botao>
        <Botao type="submit" carregando={salvando}>Abrir contrato</Botao>
      </div>
    </form>
  )
}
