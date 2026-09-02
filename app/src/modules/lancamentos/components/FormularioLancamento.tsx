import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { hojeISO } from '../../../core/formatos'
import type { Conta } from '../../contas/tipos'
import { montarArvore, type Categoria } from '../../categorias/tipos'
import { TIPOS_LANCAMENTO, type DadosLancamento, type Lancamento, type TipoLancamento } from '../tipos'

interface Props {
  lancamento?: Lancamento
  contas: Conta[]
  categorias: Categoria[]
  tipoInicial?: TipoLancamento
  salvando: boolean
  erro: string | null
  avisoDuplicidade?: string | null
  aoSalvar: (dados: DadosLancamento, ignorarDuplicidade: boolean) => void
  aoCancelar: () => void
}

interface Erros { descricao?: string; valor?: string; data?: string; conta?: string; destino?: string; categoria?: string }

export function FormularioLancamento({ lancamento, contas, categorias, tipoInicial = 'despesa', salvando, erro, avisoDuplicidade, aoSalvar, aoCancelar }: Props) {
  const editando = Boolean(lancamento)
  const [tipo, setTipo] = useState<TipoLancamento>(lancamento?.tipo ?? tipoInicial)
  const [descricao, setDescricao] = useState(lancamento?.descricao ?? '')
  const [valor, setValor] = useState(lancamento ? String(lancamento.valor) : '')
  const [data, setData] = useState(lancamento?.data_competencia ?? hojeISO())
  const [vencimento, setVencimento] = useState(lancamento?.data_vencimento ?? '')
  const [efetivado, setEfetivado] = useState(lancamento ? lancamento.status === 'efetivado' : true)
  const [dataEfetivacao, setDataEfetivacao] = useState(lancamento?.data_efetivacao ?? '')
  const [contaId, setContaId] = useState(lancamento?.conta_id ?? '')
  const [destinoId, setDestinoId] = useState(lancamento?.conta_destino_id ?? '')
  const [categoriaId, setCategoriaId] = useState(lancamento?.categoria_id ?? '')
  const [observacao, setObservacao] = useState(lancamento?.observacao ?? '')
  const [erros, setErros] = useState<Erros>({})

  const contasDisponiveis = contas.filter((c) => c.ativo || c.id === lancamento?.conta_id || c.id === lancamento?.conta_destino_id)
  const arvore = montarArvore(categorias.filter((c) => c.tipo === tipo && (c.ativo || c.id === lancamento?.categoria_id)))
  const ehTransferencia = tipo === 'transferencia'

  function montar(): DadosLancamento | null {
    const novos: Erros = {}
    const v = Number(valor.replace(',', '.'))
    if (descricao.trim().length === 0) novos.descricao = 'Informe a descrição.'
    if (valor.trim() === '' || Number.isNaN(v) || v <= 0) novos.valor = 'Informe um valor maior que zero.'
    if (!data) novos.data = 'Informe a data.'
    if (!contaId) novos.conta = ehTransferencia ? 'Informe a conta de origem.' : 'Informe a conta.'
    if (ehTransferencia && !destinoId) novos.destino = 'Informe a conta de destino.'
    if (ehTransferencia && destinoId && destinoId === contaId) novos.destino = 'Origem e destino devem ser contas diferentes.'
    if (!ehTransferencia && !categoriaId) novos.categoria = 'Informe a categoria.'
    setErros(novos)
    if (Object.keys(novos).length > 0) return null
    return {
      tipo,
      descricao: descricao.trim(),
      valor: Math.round(v * 100) / 100,
      data_competencia: data,
      data_vencimento: vencimento || data,
      data_efetivacao: efetivado ? (dataEfetivacao || data) : null,
      conta_id: contaId,
      conta_destino_id: ehTransferencia ? destinoId : null,
      categoria_id: ehTransferencia ? null : categoriaId,
      observacao: observacao.trim() || null,
    }
  }

  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const d = montar()
    if (d) aoSalvar(d, false)
  }

  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      {avisoDuplicidade && (
        <Alerta tipo="info" titulo="Possível duplicidade">
          {avisoDuplicidade}
          <div className="mt-2"><Botao type="button" variante="secundario" onClick={() => { const d = montar(); if (d) aoSalvar(d, true) }} carregando={salvando}>Salvar mesmo assim</Botao></div>
        </Alerta>
      )}

      <div role="radiogroup" aria-label="Tipo de lançamento" className="grid grid-cols-3 gap-1 rounded-md border border-line p-1">
        {TIPOS_LANCAMENTO.map((t) => (
          <button
            key={t.valor}
            type="button"
            role="radio"
            aria-checked={tipo === t.valor}
            disabled={editando}
            onClick={() => { setTipo(t.valor); setCategoriaId(''); setDestinoId('') }}
            className={`rounded px-2 py-1.5 text-sm disabled:cursor-not-allowed ${tipo === t.valor ? 'bg-brand-600 text-white' : 'text-ink-muted hover:text-ink disabled:opacity-60'}`}
          >
            {t.rotulo}
          </button>
        ))}
      </div>

      <Campo rotulo="Descrição" value={descricao} onChange={(e) => setDescricao(e.target.value)} erro={erros.descricao} autoFocus maxLength={140} />
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Valor (R$)" type="number" inputMode="decimal" step="0.01" min="0.01" value={valor} onChange={(e) => setValor(e.target.value)} erro={erros.valor} />
        <Campo rotulo="Data" type="date" value={data} onChange={(e) => setData(e.target.value)} erro={erros.data} />
      </div>

      <Selecao
        rotulo={ehTransferencia ? 'Conta de origem' : 'Conta'}
        opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...contasDisponiveis.map((c) => ({ valor: c.id, rotulo: c.nome }))]}
        value={contaId}
        onChange={(e) => setContaId(e.target.value)}
      />
      {erros.conta && <p className="-mt-3 text-xs text-red-600">{erros.conta}</p>}

      {ehTransferencia ? (
        <>
          <Selecao
            rotulo="Conta de destino"
            opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...contasDisponiveis.filter((c) => c.id !== contaId).map((c) => ({ valor: c.id, rotulo: c.nome }))]}
            value={destinoId}
            onChange={(e) => setDestinoId(e.target.value)}
          />
          {erros.destino && <p className="-mt-3 text-xs text-red-600">{erros.destino}</p>}
        </>
      ) : (
        <div className="space-y-1">
          <label htmlFor="categoria" className="block text-sm font-medium text-ink">Categoria</label>
          <select id="categoria" value={categoriaId} onChange={(e) => setCategoriaId(e.target.value)} className="h-10 w-full rounded-md border border-line bg-white px-3 text-sm outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-100">
            <option value="">Selecione…</option>
            {arvore.map(({ raiz, filhas }) => filhas.length === 0
              ? <option key={raiz.id} value={raiz.id}>{raiz.nome}</option>
              : (
                <optgroup key={raiz.id} label={raiz.nome}>
                  <option value={raiz.id}>{raiz.nome} (geral)</option>
                  {filhas.map((f) => <option key={f.id} value={f.id}>{f.nome}</option>)}
                </optgroup>
              ))}
          </select>
          {erros.categoria && <p className="text-xs text-red-600">{erros.categoria}</p>}
        </div>
      )}

      <div className="rounded-md border border-line bg-surface/60 p-3">
        <label className="flex items-center gap-2 text-sm font-medium">
          <input type="checkbox" checked={efetivado} onChange={(e) => setEfetivado(e.target.checked)} className="size-4 accent-brand-600" />
          {tipo === 'receita' ? 'Já recebido' : tipo === 'despesa' ? 'Já pago' : 'Já realizada'}
        </label>
        <div className="mt-3 grid grid-cols-2 gap-4">
          {efetivado
            ? <Campo rotulo="Data de efetivação" type="date" value={dataEfetivacao || data} onChange={(e) => setDataEfetivacao(e.target.value)} />
            : <Campo rotulo="Vencimento" type="date" value={vencimento || data} onChange={(e) => setVencimento(e.target.value)} />}
        </div>
        {!efetivado && <p className="mt-2 text-xs text-ink-muted">Lançamento previsto: não altera o saldo até ser efetivado.</p>}
      </div>

      <AreaTexto rotulo="Observação (opcional)" rows={2} maxLength={500} value={observacao} onChange={(e) => setObservacao(e.target.value)} />

      <div className="flex justify-end gap-2 pt-2">
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando}>Voltar</Botao>
        <Botao type="submit" carregando={salvando}>{editando ? 'Salvar alterações' : 'Salvar lançamento'}</Botao>
      </div>
    </form>
  )
}
