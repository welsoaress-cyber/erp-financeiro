import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { hojeISO } from '../../../core/formatos'
import type { Conta } from '../../contas/tipos'
import { montarArvore, type Categoria } from '../../categorias/tipos'
import { TIPOS_LANCAMENTO, rotuloParcela, type DadosLancamento, type Lancamento, type TipoLancamento, type TipoRecorrencia } from '../tipos'
import type { EscopoEdicaoRecorrente } from '../api'
import { SelecaoNegocio } from '../../negocios/components/SelecaoNegocio'
import { gerarSlug, type Negocio } from '../../negocios/tipos'
import type { Pessoa } from '../../pessoas/tipos'
import { codigoContrato, type Contrato } from '../../contratos/tipos'
import { useCriarConta } from '../../contas/api'
import { useCartoesConfig } from '../../cartoes/api'
import type { CartaoConfig } from '../../cartoes/tipos'
import { useCriarCategoria } from '../../categorias/api'
import { useCriarNegocio } from '../../negocios/api'
import { useCriarPessoa } from '../../pessoas/api'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'

/** Cadastro rápido sem sair do lançamento: "+ Criar…" abre um campo de nome e cria na hora. */
function CriarRapido({ rotulo, aoCriar }: { rotulo: string; aoCriar: (nome: string) => Promise<void> }) {
  const [aberto, setAberto] = useState(false)
  const [nome, setNome] = useState('')
  const [criando, setCriando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  if (!aberto) {
    return <button type="button" className="block text-xs font-medium text-brand-600 hover:underline" onClick={() => setAberto(true)}>+ {rotulo}</button>
  }
  async function confirmar() {
    if (nome.trim().length < 2 || criando) return
    setCriando(true); setErro(null)
    try {
      await aoCriar(nome.trim())
      setNome(''); setAberto(false)
    } catch (e) {
      setErro(mensagemDeErro(e))
    } finally {
      setCriando(false)
    }
  }
  return (
    <div className="space-y-1 rounded-md border border-line bg-surface/60 p-2">
      <div className="flex items-center gap-2">
        <input
          value={nome}
          onChange={(e) => setNome(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); void confirmar() } }}
          placeholder="Nome"
          autoFocus
          className="h-8 flex-1 rounded-md border border-line bg-white px-2 text-sm outline-none focus:border-brand-600"
        />
        <Botao type="button" onClick={() => void confirmar()} carregando={criando} disabled={nome.trim().length < 2}>Criar</Botao>
        <Botao type="button" variante="secundario" onClick={() => { setAberto(false); setErro(null) }}>×</Botao>
      </div>
      {erro && <p className="text-xs text-red-600">{erro}</p>}
    </div>
  )
}

/** Criação rápida de categoria com pai opcional: sem pai = categoria; com pai = subcategoria. */
function CriarRapidoCategoria({ tipo, raizes, aoCriar }: { tipo: 'receita' | 'despesa'; raizes: Categoria[]; aoCriar: (nome: string, paiId: string | null) => Promise<void> }) {
  const [aberto, setAberto] = useState(false)
  const [nome, setNome] = useState('')
  const [paiId, setPaiId] = useState('')
  const [criando, setCriando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  if (!aberto) {
    return <button type="button" className="block text-xs font-medium text-brand-600 hover:underline" onClick={() => setAberto(true)}>+ Criar categoria de {tipo}</button>
  }
  async function confirmar() {
    if (nome.trim().length < 2 || criando) return
    setCriando(true); setErro(null)
    try {
      await aoCriar(nome.trim(), paiId || null)
      setNome(''); setPaiId(''); setAberto(false)
    } catch (e) {
      setErro(mensagemDeErro(e))
    } finally {
      setCriando(false)
    }
  }
  return (
    <div className="space-y-2 rounded-md border border-line bg-surface/60 p-2">
      <div className="flex items-center gap-2">
        <input
          value={nome}
          onChange={(e) => setNome(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); void confirmar() } }}
          placeholder="Nome"
          autoFocus
          className="h-8 flex-1 rounded-md border border-line bg-white px-2 text-sm outline-none focus:border-brand-600"
        />
        <Botao type="button" onClick={() => void confirmar()} carregando={criando} disabled={nome.trim().length < 2}>Criar</Botao>
        <Botao type="button" variante="secundario" onClick={() => { setAberto(false); setErro(null) }}>×</Botao>
      </div>
      {raizes.length > 0 && (
        <select aria-label="Categoria pai (opcional)" value={paiId} onChange={(e) => setPaiId(e.target.value)} className="h-8 w-full rounded-md border border-line bg-white px-2 text-sm outline-none focus:border-brand-600">
          <option value="">Sem pai (categoria principal)</option>
          {raizes.map((c) => <option key={c.id} value={c.id}>Subcategoria de: {c.nome}</option>)}
        </select>
      )}
      {erro && <p className="text-xs text-red-600">{erro}</p>}
    </div>
  )
}

interface Props {
  lancamento?: Lancamento
  contas: Conta[]
  categorias: Categoria[]
  negocios: Negocio[]
  pessoas: Pessoa[]
  contratos: Contrato[]
  negocioInicial?: string | null
  tipoInicial?: TipoLancamento
  salvando: boolean
  erro: string | null
  avisoDuplicidade?: string | null
  /** edição: já existe a próxima parcela gerada a partir deste lançamento */
  proximaGerada?: boolean
  aoSalvar: (dados: DadosLancamento, ignorarDuplicidade: boolean) => void
  /** edição de recorrente com parcela já gerada: salva descrição/valor/observação no escopo escolhido */
  aoSalvarLote?: (dados: { descricao: string; valor: number; observacao: string | null; escopo: EscopoEdicaoRecorrente; data_vencimento?: string | null }) => void
  aoCancelar: () => void
}

/** Vencimento da fatura em que uma compra na data informada entra (mesma regra do fechamento no banco). */
function vencimentoFatura(dataISO: string, cfg: CartaoConfig): string {
  const [ano, mes, dia] = dataISO.split('-').map(Number)
  let fAno = ano
  let fMes = mes
  if (dia > cfg.dia_fechamento) { fMes++; if (fMes > 12) { fMes = 1; fAno++ } }
  if (cfg.dia_vencimento <= cfg.dia_fechamento) { fMes++; if (fMes > 12) { fMes = 1; fAno++ } }
  return `${fAno}-${String(fMes).padStart(2, '0')}-${String(cfg.dia_vencimento).padStart(2, '0')}`
}

interface Erros { descricao?: string; valor?: string; data?: string; conta?: string; destino?: string; categoria?: string; recorrencia?: string }

export function FormularioLancamento({ lancamento, contas, categorias, negocios, pessoas, contratos, negocioInicial = null, tipoInicial = 'despesa', salvando, erro, avisoDuplicidade, proximaGerada = false, aoSalvar, aoSalvarLote, aoCancelar }: Props) {
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
  const [negocioId, setNegocioId] = useState<string | null>(lancamento ? lancamento.negocio_id : negocioInicial)
  const [pessoaId, setPessoaId] = useState<string>(lancamento?.pessoa_id ?? '')
  const pessoasDisponiveis = pessoas.filter((p) => p.ativo || p.id === lancamento?.pessoa_id)
  const [contratoId, setContratoId] = useState<string>(lancamento?.contrato_id ?? '')
  const contratosDisponiveis = contratos.filter((c) => (c.status !== 'encerrado' || c.id === lancamento?.contrato_id) && (!negocioId || c.negocio_id === negocioId))
  const contratoSel = contratos.find((c) => c.id === contratoId)
  function escolherContrato(id: string) {
    setContratoId(id)
    const c = contratos.find((x) => x.id === id)
    if (c) { setNegocioId(c.negocio_id); setPessoaId(c.pessoa_id) }
  }
  const [erros, setErros] = useState<Erros>({})
  const [escopo, setEscopo] = useState<EscopoEdicaoRecorrente>('atual')
  const [recorrente, setRecorrente] = useState(lancamento?.recorrente ?? false)
  const [tipoRec, setTipoRec] = useState<TipoRecorrencia>(lancamento?.tipo_recorrencia ?? (lancamento?.numero_parcelas ? 'parcelada' : 'fixa'))
  const [numeroParcelas, setNumeroParcelas] = useState(lancamento?.numero_parcelas ? String(lancamento.numero_parcelas) : '')
  const [parcelaInicial, setParcelaInicial] = useState(lancamento?.parcela_atual && lancamento.parcela_atual > 1 && !lancamento.lancamento_origem_id ? String(lancamento.parcela_atual) : '1')
  // periodicidade e término ficam no banco (compatibilidade); a tela trabalha com fixa (mensal, sem fim) e parcelamento (N parcelas)
  const periodicidade = lancamento?.periodicidade ?? 'mensal'
  const dataFimRecorrencia = lancamento?.data_fim_recorrencia ?? ''
  const parcelaGerada = lancamento?.recorrente === true && ((lancamento.parcela_atual ?? 1) > 1 || proximaGerada)
  // com parcelas geradas só descrição e observação mudam (regra do banco)
  const travado = lancamento?.recorrente === true && proximaGerada
  const ehFaturamento = lancamento?.origem === 'faturamento'

  const criarConta = useCriarConta()
  const criarCategoria = useCriarCategoria()
  const criarNegocio = useCriarNegocio()
  const criarPessoa = useCriarPessoa()

  const contasDisponiveis = contas.filter((c) => c.ativo || c.id === lancamento?.conta_id || c.id === lancamento?.conta_destino_id)
  const arvore = montarArvore(categorias.filter((c) => c.tipo === tipo && (c.ativo || c.id === lancamento?.categoria_id)))
  const ehTransferencia = tipo === 'transferencia'

  // Compra no cartão de crédito: entra na fatura, sem "já pago" nem vencimento manual
  const configCartoes = useCartoesConfig().data ?? []
  const contaSel = contas.find((c) => c.id === contaId)
  const cartaoCfg = contaSel?.tipo === 'credito' ? configCartoes.find((k) => k.conta_id === contaSel.id) : undefined
  const ehCartao = !ehTransferencia && contaSel?.tipo === 'credito' && (!lancamento || lancamento.status === 'previsto')
  const vencCartao = ehCartao && cartaoCfg && data ? vencimentoFatura(data, cartaoCfg) : null

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
    const nParcelas = recorrente && tipoRec === 'parcelada' ? (numeroParcelas.trim() === '' ? null : Number(numeroParcelas)) : null
    const nInicial = recorrente && tipoRec === 'parcelada' ? Number(parcelaInicial || '1') : 1
    if (recorrente && tipoRec === 'parcelada') {
      if (nParcelas === null) novos.recorrencia = 'Informe o número de parcelas.'
      else if (!Number.isInteger(nParcelas) || nParcelas < 2 || nParcelas > 360) novos.recorrencia = 'Número de parcelas entre 2 e 360.'
      else if (!Number.isInteger(nInicial) || nInicial < 1 || nInicial > nParcelas) novos.recorrencia = 'A parcela inicial deve estar entre 1 e o total de parcelas.'
    }
    setErros(novos)
    if (Object.keys(novos).length > 0) return null
    return {
      tipo,
      descricao: descricao.trim(),
      valor: Math.round(v * 100) / 100,
      data_competencia: data,
      data_vencimento: ehCartao ? (vencCartao ?? data) : (vencimento || data),
      data_efetivacao: ehCartao ? null : efetivado ? (dataEfetivacao || data) : null,
      conta_id: contaId,
      conta_destino_id: ehTransferencia ? destinoId : null,
      categoria_id: ehTransferencia ? null : categoriaId,
      observacao: observacao.trim() || null,
      negocio_id: negocioId,
      pessoa_id: pessoaId || null,
      contrato_id: contratoId || null,
      recorrente,
      periodicidade: recorrente ? periodicidade : null,
      numero_parcelas: recorrente ? nParcelas : null,
      parcela_inicial: recorrente && tipoRec === 'parcelada' ? nInicial : 1,
      data_fim_recorrencia: recorrente && dataFimRecorrencia ? dataFimRecorrencia : null,
    }
  }

  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (travado && aoSalvarLote) {
      const v = Number(valor.replace(',', '.'))
      const novos: Erros = {}
      if (descricao.trim().length === 0) novos.descricao = 'Informe a descrição.'
      if (valor.trim() === '' || Number.isNaN(v) || v <= 0) novos.valor = 'Informe um valor maior que zero.'
      setErros(novos)
      if (Object.keys(novos).length > 0) return
      const dataMudou = escopo !== 'todas' && lancamento?.status === 'previsto' && data !== lancamento.data_competencia
      aoSalvarLote({ descricao: descricao.trim(), valor: Math.round(v * 100) / 100, observacao: observacao.trim() || null, escopo, data_vencimento: dataMudou ? data : null })
      return
    }
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

      {travado && (
        <Alerta tipo="info" titulo="Parcelas já geradas">
          Este lançamento recorrente já gerou a próxima parcela: descrição, valor, observação e data podem ser alterados (data só em "apenas esta" ou "esta e as futuras" — as futuras deslocam junto para o novo dia).
          {aoSalvarLote && (
            <div role="radiogroup" aria-label="Alcance da alteração" className="mt-3 space-y-1.5">
              <label className="flex items-start gap-2 text-sm"><input type="radio" name="escopo" checked={escopo === 'atual'} onChange={() => setEscopo('atual')} className="mt-0.5 accent-brand-600" /><span><b>Apenas esta parcela</b><span className="block text-xs text-ink-muted">Só esta ocorrência muda.</span></span></label>
              <label className="flex items-start gap-2 text-sm"><input type="radio" name="escopo" checked={escopo === 'futuras'} onChange={() => setEscopo('futuras')} className="mt-0.5 accent-brand-600" /><span><b>Esta e as futuras</b><span className="block text-xs text-ink-muted">Muda esta e as próximas já geradas; as anteriores (inclusive já pagas) continuam como estavam.</span></span></label>
              <label className="flex items-start gap-2 text-sm"><input type="radio" name="escopo" checked={escopo === 'todas'} onChange={() => setEscopo('todas')} className="mt-0.5 accent-brand-600" /><span><b>Todas as parcelas, inclusive já pagas</b><span className="block text-xs text-amber-800">Reescreve o histórico inteiro desta recorrência — use com cuidado.</span></span></label>
            </div>
          )}
        </Alerta>
      )}

      <Campo rotulo="Descrição" value={descricao} onChange={(e) => setDescricao(e.target.value)} erro={erros.descricao} autoFocus maxLength={140} />
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Valor (R$)" type="number" inputMode="decimal" step="0.01" min="0.01" value={valor} onChange={(e) => setValor(e.target.value)} erro={erros.valor} />
        <Campo rotulo="Data" type="date" value={data} onChange={(e) => setData(e.target.value)} erro={erros.data} disabled={travado && (escopo === 'todas' || lancamento?.status !== 'previsto')} />
      </div>

      <Selecao
        rotulo={ehTransferencia ? 'Conta de origem' : 'Conta'}
        opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...contasDisponiveis.map((c) => ({ valor: c.id, rotulo: c.nome }))]}
        value={contaId}
        onChange={(e) => setContaId(e.target.value)}
        disabled={travado}
      />
      {erros.conta && <p className="-mt-3 text-xs text-red-600">{erros.conta}</p>}
      {!travado && (
        <CriarRapido rotulo="Criar conta" aoCriar={async (nome) => {
          const c = await criarConta.mutateAsync({ nome, tipo: 'corrente', saldo_inicial: 0, data_inicio: hojeISO(), ativo: true, negocio_id: negocioId })
          setContaId(c.id)
        }} />
      )}

      {ehTransferencia ? (
        <>
          <Selecao
            rotulo="Conta de destino"
            opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...contasDisponiveis.filter((c) => c.id !== contaId).map((c) => ({ valor: c.id, rotulo: c.nome }))]}
            value={destinoId}
            onChange={(e) => setDestinoId(e.target.value)}
            disabled={travado}
          />
          {erros.destino && <p className="-mt-3 text-xs text-red-600">{erros.destino}</p>}
        </>
      ) : (
        <div className="space-y-1">
          <label htmlFor="categoria" className="block text-sm font-medium text-ink">Categoria</label>
          <select id="categoria" value={categoriaId} onChange={(e) => setCategoriaId(e.target.value)} disabled={travado} className="disabled:bg-surface disabled:text-ink-muted h-10 w-full rounded-md border border-line bg-white px-3 text-sm outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-100">
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
          {!travado && (
            <CriarRapidoCategoria
              tipo={tipo as 'receita' | 'despesa'}
              raizes={arvore.map(({ raiz }) => raiz)}
              aoCriar={async (nome, paiId) => {
                const c = await criarCategoria.mutateAsync({ nome, tipo: tipo as 'receita' | 'despesa', categoria_pai_id: paiId, natureza: arvore.find(({ raiz }) => raiz.id === paiId)?.raiz.natureza ?? 'operacional', ativo: true })
                setCategoriaId(c.id)
              }}
            />
          )}
        </div>
      )}

      {ehCartao ? (
        <div className="rounded-md border border-line bg-surface/60 p-3 text-sm">
          <p className="font-medium">Compra no cartão de crédito</p>
          {vencCartao
            ? <p className="mt-1 text-xs text-ink-muted">Entra na fatura com vencimento em {vencCartao.split('-').reverse().join('/')} e é efetivada no fechamento do cartão.</p>
            : <p className="mt-1 text-xs text-amber-800">Cartão sem configuração de fechamento/vencimento: configure em Cartões. Por enquanto o vencimento fica na data da compra.</p>}
        </div>
      ) : (
      <div className="rounded-md border border-line bg-surface/60 p-3">
        <label className="flex items-center gap-2 text-sm font-medium">
          <input type="checkbox" checked={efetivado} onChange={(e) => setEfetivado(e.target.checked)} className="size-4 accent-brand-600" />
          {tipo === 'receita' ? 'Já recebido' : tipo === 'despesa' ? 'Já pago' : 'Já realizada'}
        </label>
        <div className="mt-3 grid grid-cols-2 gap-4">
          {efetivado
            ? <Campo rotulo="Data de efetivação" type="date" value={dataEfetivacao || data} onChange={(e) => setDataEfetivacao(e.target.value)} />
            : <Campo rotulo="Vencimento" type="date" value={vencimento || data} onChange={(e) => setVencimento(e.target.value)} disabled={travado} />}
        </div>
        {!efetivado && <p className="mt-2 text-xs text-ink-muted">Lançamento previsto: não altera o saldo até ser efetivado.</p>}
      </div>
      )}

      {!ehFaturamento && (
        <div className="rounded-md border border-line bg-surface/60 p-3">
          <label className="flex items-center gap-2 text-sm font-medium">
            <input type="checkbox" checked={recorrente} onChange={(e) => setRecorrente(e.target.checked)} disabled={parcelaGerada} className="size-4 accent-brand-600" />
            Lançamento recorrente
            {lancamento && rotuloParcela(lancamento) && <span className="ml-auto text-xs font-normal text-ink-muted">{rotuloParcela(lancamento)}</span>}
          </label>
          {!recorrente && <p className="mt-1 text-xs text-ink-muted">Avulso: acontece uma vez e não se repete.</p>}
          {recorrente && (
            <>
              <div role="radiogroup" aria-label="Tipo de recorrência" className="mt-3 grid gap-2 sm:grid-cols-2">
                <label className={`flex cursor-pointer items-start gap-2 rounded-md border p-2 text-sm ${tipoRec === 'fixa' ? 'border-brand-600 bg-brand-50' : 'border-line'}`}>
                  <input type="radio" name="tipo-recorrencia" value="fixa" checked={tipoRec === 'fixa'} onChange={() => setTipoRec('fixa')} disabled={parcelaGerada} className="mt-0.5 accent-brand-600" />
                  <span><span className="font-medium">{tipo === 'receita' ? 'Receita fixa' : 'Despesa fixa'}</span><span className="block text-xs text-ink-muted">Gera todo mês até cancelar (aluguel, internet, salário).</span></span>
                </label>
                <label className={`flex cursor-pointer items-start gap-2 rounded-md border p-2 text-sm ${tipoRec === 'parcelada' ? 'border-brand-600 bg-brand-50' : 'border-line'}`}>
                  <input type="radio" name="tipo-recorrencia" value="parcelada" checked={tipoRec === 'parcelada'} onChange={() => setTipoRec('parcelada')} disabled={parcelaGerada} className="mt-0.5 accent-brand-600" />
                  <span><span className="font-medium">Parcelamento</span><span className="block text-xs text-ink-muted">Valor dividido em N parcelas; para na última.</span></span>
                </label>
              </div>
              {tipoRec === 'parcelada' && (
                <>
                <div className="mt-3 grid grid-cols-3 gap-4">
                  <Campo rotulo="Número de parcelas" type="number" inputMode="numeric" min={2} max={360} step={1} placeholder="Ex.: 24" value={numeroParcelas} onChange={(e) => setNumeroParcelas(e.target.value)} disabled={parcelaGerada} />
                  <Campo rotulo="Iniciar a partir da parcela" type="number" inputMode="numeric" min={1} max={360} step={1} value={parcelaInicial} onChange={(e) => setParcelaInicial(e.target.value)} disabled={parcelaGerada} title="Já pagou parcelas fora do sistema? Informe de qual continuar." />
                  <Campo rotulo={Number(parcelaInicial || '1') > 1 ? `Início (parcela ${parcelaInicial})` : 'Início (1ª parcela)'} type="date" value={vencimento || data} onChange={(e) => { setVencimento(e.target.value); if (!editando) setData(e.target.value) }} disabled={parcelaGerada} />
                </div>
                {Number(parcelaInicial || '1') > 1 && Number(numeroParcelas) >= Number(parcelaInicial) && valor.trim() !== '' && !Number.isNaN(Number(valor.replace(',', '.'))) && (
                  <p className="mt-2 rounded-md bg-surface px-3 py-2 text-xs text-ink-muted">
                    Contrato: <b>{numeroParcelas}×</b> de <b>{Number(valor.replace(',', '.')).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })}</b> = {(Number(numeroParcelas) * Number(valor.replace(',', '.'))).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })}
                    {' · '}pagas fora do sistema: {Number(parcelaInicial) - 1}× ({((Number(parcelaInicial) - 1) * Number(valor.replace(',', '.'))).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })})
                    {' · '}restam: {Number(numeroParcelas) - Number(parcelaInicial) + 1}× ({((Number(numeroParcelas) - Number(parcelaInicial) + 1) * Number(valor.replace(',', '.'))).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })})
                  </p>
                )}
                </>
              )}
              {erros.recorrencia && <p className="mt-1 text-xs text-red-600">{erros.recorrencia}</p>}
              <p className="mt-2 text-xs text-ink-muted">
                {parcelaGerada
                  ? 'O tipo de recorrência e o número de parcelas não mudam depois que uma parcela foi gerada.'
                  : tipoRec === 'fixa'
                    ? 'Ao efetivar (pagar/receber), o mês seguinte é criado como previsto com os mesmos dados. Só para quando você cancelar.'
                    : 'Ao efetivar cada parcela, a próxima é criada como prevista. Após a última parcela, para automaticamente.'}
              </p>
            </>
          )}
        </div>
      )}

      {negocios.some((n) => n.ativo || n.id === lancamento?.negocio_id) && (
        <SelecaoNegocio negocios={negocios} valor={negocioId} aoMudar={(id) => { setNegocioId(id); setContratoId('') }} atualId={lancamento?.negocio_id} />
      )}
      {!ehFaturamento && (
        <CriarRapido rotulo="Criar negócio" aoCriar={async (nome) => {
          const n = await criarNegocio.mutateAsync({ nome, slug: gerarSlug(nome), ativo: true, conta_padrao_id: null, categoria_receita_id: null, categoria_despesa_id: null, usa_carteira: false })
          setNegocioId(n.id); setContratoId('')
        }} />
      )}
      {!ehTransferencia && contratosDisponiveis.length > 0 && (
        <Selecao rotulo="Contrato (opcional)" opcoes={[{ valor: '', rotulo: 'Nenhum' }, ...contratosDisponiveis.map((c) => ({ valor: c.id, rotulo: `${codigoContrato(c)} · ${pessoas.find((p) => p.id === c.pessoa_id)?.nome ?? '—'}` }))]} value={contratoId} onChange={(e) => escolherContrato(e.target.value)} ajuda={contratoSel ? 'Negócio e pessoa seguem o contrato.' : 'Vincule ao contrato para medir a rentabilidade por contrato.'} />
      )}

      {pessoasDisponiveis.length > 0 && !ehTransferencia && (
        <Selecao rotulo="Pessoa (opcional)" opcoes={[{ valor: '', rotulo: 'Nenhuma' }, ...pessoasDisponiveis.map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={pessoaId} onChange={(e) => setPessoaId(e.target.value)} disabled={Boolean(contratoSel)} ajuda={contratoSel ? 'Definida pelo contrato.' : 'Cliente ou fornecedor relacionado a este lançamento.'} />
      )}
      {!ehTransferencia && !contratoSel && (
        <CriarRapido rotulo="Criar pessoa" aoCriar={async (nome) => {
          const p = await criarPessoa.mutateAsync({ tipo: 'fisica', nome, documento: null, email: null, telefone: null, data_nascimento: null, observacao: null, ativo: true, receber_avisos: true })
          setPessoaId(p.id)
        }} />
      )}

      <AreaTexto rotulo="Observação (opcional)" rows={2} maxLength={500} value={observacao} onChange={(e) => setObservacao(e.target.value)} />

      <div className="flex justify-end gap-2 pt-2">
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando}>Voltar</Botao>
        <Botao type="submit" carregando={salvando}>{editando ? 'Salvar alterações' : 'Salvar lançamento'}</Botao>
      </div>
    </form>
  )
}
