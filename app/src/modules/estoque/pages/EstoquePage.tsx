import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { Carregando } from '../../../core/ui/Carregando'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { ImportarPrint } from '../components/ImportarPrint'
import { formatarData, formatarMoeda, hojeISO } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useCategorias } from '../../categorias/api'
import { useContas } from '../../contas/api'
import { useCriarLancamento } from '../../lancamentos/api'
import { useAjusteEstoque, useConsumoItem, useConsumoMensal, useEntradaEstoque, useEstoqueCategorias, useEstoqueItens, useEstoqueMovs, useInstalacoes, useSaidaEstoque, useSalvarEstoqueCategoria, useSalvarEstoqueItem } from '../api'
import { NovaInstalacao } from '../components/NovaInstalacao'
import { fmtQtd, ROTULO_ORIGEM, statusItem, UNIDADES, type EstoqueItem, type Unidade } from '../tipos'
import { AbaComodato } from '../components/AbaComodato'

type Aba = 'dashboard' | 'itens' | 'movs' | 'instalacoes' | 'comodato' | 'relatorios' | 'categorias'
const TOM_STATUS = { zerado: 'alerta', baixo: 'alerta', excesso: 'info', ok: 'ok' } as const

function FormularioItem({ item, negocioId, salvando, erro, aoSalvar, aoCancelar }: {
  item?: EstoqueItem; negocioId: string; salvando: boolean; erro: string | null
  aoSalvar: (d: Parameters<ReturnType<typeof useSalvarEstoqueItem>['mutate']>[0]) => void; aoCancelar: () => void
}) {
  const categorias = useEstoqueCategorias()
  const cats = (categorias.data ?? []).filter((c) => c.negocio_id === (item?.negocio_id ?? negocioId) && (c.ativo || c.id === item?.categoria_id))
  const [categoriaId, setCategoriaId] = useState(item?.categoria_id ?? '')
  const [codigo, setCodigo] = useState(item?.codigo ?? '')
  const [nome, setNome] = useState(item?.nome ?? '')
  const [unidade, setUnidade] = useState<Unidade>(item?.unidade_medida ?? 'unidade')
  const [marca, setMarca] = useState(item?.marca ?? '')
  const [modelo, setModelo] = useState(item?.modelo ?? '')
  const [venda, setVenda] = useState(item?.valor_venda != null ? String(item.valor_venda) : '')
  const [minima, setMinima] = useState(String(item?.quantidade_minima ?? 0))
  const [maxima, setMaxima] = useState(item?.quantidade_maxima != null ? String(item.quantidade_maxima) : '')
  const [localizacao, setLocalizacao] = useState(item?.localizacao ?? '')
  const [descricao, setDescricao] = useState(item?.descricao ?? '')
  const [ativo, setAtivo] = useState(item?.ativo ?? true)
  const [erroForm, setErroForm] = useState<string | null>(null)
  function enviar() {
    if (!categoriaId) { setErroForm('Escolha a categoria.'); return }
    if (codigo.trim().length < 2 || nome.trim().length < 2) { setErroForm('Informe código e nome.'); return }
    setErroForm(null)
    aoSalvar({
      id: item?.id, negocio_id: item?.negocio_id ?? negocioId, categoria_id: categoriaId, codigo: codigo.trim().toUpperCase(), nome: nome.trim(),
      descricao: descricao.trim() || null, unidade_medida: unidade, marca: marca.trim() || null, modelo: modelo.trim() || null,
      valor_venda: venda.trim() ? Math.round(Number(venda.replace(',', '.')) * 100) / 100 : null,
      quantidade_minima: Number(minima.replace(',', '.')) || 0,
      quantidade_maxima: maxima.trim() ? Number(maxima.replace(',', '.')) : null,
      localizacao: localizacao.trim() || null, ativo,
    })
  }
  return (
    <div className="space-y-4">
      {(erro ?? erroForm) && <Alerta tipo="erro">{erro ?? erroForm}</Alerta>}
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Código" value={codigo} onChange={(e) => setCodigo(e.target.value)} maxLength={20} placeholder="Ex.: CABO-01" />
        <Selecao rotulo="Categoria" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...cats.map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={categoriaId} onChange={(e) => setCategoriaId(e.target.value)} />
      </div>
      <Campo rotulo="Nome" value={nome} onChange={(e) => setNome(e.target.value)} maxLength={80} placeholder="Ex.: Cabo drop 1FO" />
      <div className="grid grid-cols-3 gap-4">
        <Selecao rotulo="Unidade" opcoes={UNIDADES.map((u) => ({ valor: u, rotulo: u }))} value={unidade} onChange={(e) => setUnidade(e.target.value as Unidade)} />
        <Campo rotulo="Marca (opcional)" value={marca} onChange={(e) => setMarca(e.target.value)} maxLength={60} />
        <Campo rotulo="Modelo (opcional)" value={modelo} onChange={(e) => setModelo(e.target.value)} maxLength={60} />
      </div>
      <div className="grid grid-cols-3 gap-4">
        <Campo rotulo="Qtd. mínima (alerta)" type="number" step="0.01" min="0" value={minima} onChange={(e) => setMinima(e.target.value)} />
        <Campo rotulo="Qtd. máxima (opcional)" type="number" step="0.01" min="0" value={maxima} onChange={(e) => setMaxima(e.target.value)} />
        <Campo rotulo="Valor de venda (opcional)" type="number" step="0.01" min="0" value={venda} onChange={(e) => setVenda(e.target.value)} />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Localização (opcional)" value={localizacao} onChange={(e) => setLocalizacao(e.target.value)} maxLength={100} placeholder="Ex.: prateleira 2" />
        <Campo rotulo="Descrição (opcional)" value={descricao} onChange={(e) => setDescricao(e.target.value)} maxLength={300} />
      </div>
      {item && <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />Item ativo</label>}
      {!item && <p className="text-xs text-ink-muted">O item nasce zerado: lance a quantidade inicial com um Ajuste (inventário) ou uma Compra.</p>}
      <div className="flex justify-end gap-2">
        <Botao variante="secundario" onClick={aoCancelar} disabled={salvando}>Cancelar</Botao>
        <Botao onClick={enviar} carregando={salvando}>{item ? 'Salvar alterações' : 'Criar item'}</Botao>
      </div>
    </div>
  )
}

interface LinhaCompra { itemId: string; quantidade: string; valorTotal: string }
interface LinhaPagto { contaId: string; valor: string; pago: boolean }

function NovaCompra({ negocioId, itens, aoFechar }: { negocioId: string; itens: EstoqueItem[]; aoFechar: () => void }) {
  const contas = useContas()
  const categorias = useCategorias()
  const criarLancamento = useCriarLancamento()
  const entrada = useEntradaEstoque()
  const [data, setData] = useState(hojeISO())
  const [descricao, setDescricao] = useState('Compra de estoque')
  const [categoriaId, setCategoriaId] = useState('')
  const [linhas, setLinhas] = useState<LinhaCompra[]>([{ itemId: '', quantidade: '', valorTotal: '' }])
  const [pagtos, setPagtos] = useState<LinhaPagto[]>([{ contaId: '', valor: '', pago: true }])
  const [erro, setErro] = useState<string | null>(null)
  const [salvando, setSalvando] = useState(false)
  const [importando, setImportando] = useState(false)
  const catsDespesa = (categorias.data ?? []).filter((c) => c.tipo === 'despesa' && c.ativo)
  const totalItens = linhas.reduce((s, l) => s + (Number(l.valorTotal.replace(',', '.')) || 0), 0)
  const totalPagto = pagtos.reduce((s, p) => s + (Number(p.valor.replace(',', '.')) || 0), 0)
  const contaDe = (id: string) => (contas.data ?? []).find((c) => c.id === id)

  async function salvar() {
    setErro(null)
    const itensOk = linhas.filter((l) => l.itemId && Number(l.quantidade.replace(',', '.')) > 0 && Number(l.valorTotal.replace(',', '.')) >= 0)
    if (itensOk.length === 0) { setErro('Adicione ao menos um item com quantidade e valor.'); return }
    if (!categoriaId) { setErro('Escolha a categoria da despesa (ex.: Compra de Estoque).'); return }
    const pagtosOk = pagtos.filter((p) => p.contaId && Number(p.valor.replace(',', '.')) > 0)
    if (pagtosOk.length === 0) { setErro('Informe ao menos uma forma de pagamento.'); return }
    if (Math.abs(totalPagto - totalItens) > 0.01) { setErro(`Pagamentos (${formatarMoeda(totalPagto)}) diferentes do total dos itens (${formatarMoeda(totalItens)}).`); return }
    setSalvando(true)
    try {
      // pagamento misto: um lançamento de despesa por forma; cartão de crédito entra como previsto (vai para a fatura)
      let primeiroLancamento: string | null = null
      for (const p of pagtosOk) {
        const conta = contaDe(p.contaId)
        const ehCartao = conta?.tipo === 'credito'
        const l = await criarLancamento.mutateAsync({
          tipo: 'despesa', descricao: `${descricao.trim() || 'Compra de estoque'}${pagtosOk.length > 1 ? ` (${conta?.nome})` : ''}`,
          valor: Math.round(Number(p.valor.replace(',', '.')) * 100) / 100,
          data_competencia: data, data_vencimento: data,
          data_efetivacao: !ehCartao && p.pago ? data : null,
          conta_id: p.contaId, conta_destino_id: null, categoria_id: categoriaId,
          observacao: 'Entrada de estoque', negocio_id: negocioId, pessoa_id: null, contrato_id: null,
          recorrente: false, periodicidade: null, numero_parcelas: null, data_fim_recorrencia: null,
        })
        primeiroLancamento ??= (l as { id: string }).id
      }
      for (const l of itensOk) {
        await entrada.mutateAsync({
          item_id: l.itemId, quantidade: Number(l.quantidade.replace(',', '.')),
          valor_total: Math.round(Number(l.valorTotal.replace(',', '.')) * 100) / 100,
          data, origem: 'compra', lancamento_id: primeiroLancamento, observacao: descricao.trim() || null,
        })
      }
      aoFechar()
    } catch (e) {
      setErro(mensagemDeErro(e))
    } finally {
      setSalvando(false)
    }
  }

  return (
    <div className="space-y-4">
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      {importando ? (
        <ImportarPrint
          aoFechar={() => setImportando(false)}
          aoExtrair={(d) => {
            if (d.descricao) setDescricao(d.descricao)
            const total = d.total != null ? String(d.total.toFixed(2)).replace('.', ',') : ''
            setLinhas((xs) => [{ ...xs[0], quantidade: d.quantidade != null ? String(d.quantidade) : xs[0].quantidade || '1', valorTotal: total || xs[0].valorTotal }, ...xs.slice(1)])
            if (total) setPagtos((xs) => [{ ...xs[0], valor: total }, ...xs.slice(1)])
            setImportando(false)
          }}
        />
      ) : (
        <Botao variante="secundario" onClick={() => setImportando(true)}>📷 Importar de print (Shopee, Mercado Livre…)</Botao>
      )}
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Data" type="date" value={data} onChange={(e) => setData(e.target.value)} />
        <Selecao rotulo="Categoria da despesa" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...catsDespesa.map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={categoriaId} onChange={(e) => setCategoriaId(e.target.value)} />
      </div>
      <Campo rotulo="Descrição" value={descricao} onChange={(e) => setDescricao(e.target.value)} maxLength={140} />
      <div>
        <p className="mb-1 text-sm font-medium">Itens comprados (valor = total pago naquele item; o custo unitário é rateado)</p>
        {linhas.map((l, i) => (
          <div key={i} className="mb-2 flex items-end gap-2">
            <div className="flex-1"><Selecao rotulo={i === 0 ? 'Item' : ''} opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...itens.filter((x) => x.ativo).map((x) => ({ valor: x.id, rotulo: `${x.codigo} · ${x.nome} (${x.unidade_medida})` }))]} value={l.itemId} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, itemId: e.target.value } : x)))} /></div>
            <input type="number" step="0.01" min="0.01" placeholder="Qtd." value={l.quantidade} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, quantidade: e.target.value } : x)))} className="h-10 w-24 rounded-md border border-line bg-white px-2 text-sm" />
            <input type="number" step="0.01" min="0" placeholder="Valor total R$" value={l.valorTotal} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, valorTotal: e.target.value } : x)))} className="h-10 w-32 rounded-md border border-line bg-white px-2 text-sm" />
            <button type="button" aria-label="Remover item" className="pb-2 text-ink-muted hover:text-red-700" onClick={() => setLinhas((xs) => xs.filter((_, j) => j !== i))}>×</button>
          </div>
        ))}
        <Botao variante="secundario" onClick={() => setLinhas((xs) => [...xs, { itemId: '', quantidade: '', valorTotal: '' }])}>+ Item</Botao>
      </div>
      <div>
        <p className="mb-1 text-sm font-medium">Pagamento (pode dividir: cartão + Pix, etc. Cartão de crédito vai para a fatura)</p>
        {pagtos.map((p, i) => (
          <div key={i} className="mb-2 flex items-end gap-2">
            <div className="flex-1"><Selecao rotulo={i === 0 ? 'Conta' : ''} opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(contas.data ?? []).filter((c) => c.ativo).map((c) => ({ valor: c.id, rotulo: `${c.nome}${c.tipo === 'credito' ? ' (cartão)' : ''}` }))]} value={p.contaId} onChange={(e) => setPagtos((xs) => xs.map((x, j) => (j === i ? { ...x, contaId: e.target.value } : x)))} /></div>
            <input type="number" step="0.01" min="0.01" placeholder="Valor R$" value={p.valor} onChange={(e) => setPagtos((xs) => xs.map((x, j) => (j === i ? { ...x, valor: e.target.value } : x)))} className="h-10 w-32 rounded-md border border-line bg-white px-2 text-sm" />
            {contaDe(p.contaId)?.tipo !== 'credito' && (
              <label className="flex items-center gap-1 pb-2.5 text-sm"><input type="checkbox" checked={p.pago} onChange={(e) => setPagtos((xs) => xs.map((x, j) => (j === i ? { ...x, pago: e.target.checked } : x)))} className="size-4 accent-brand-600" />Pago</label>
            )}
            <button type="button" aria-label="Remover pagamento" className="pb-2 text-ink-muted hover:text-red-700" onClick={() => setPagtos((xs) => xs.filter((_, j) => j !== i))}>×</button>
          </div>
        ))}
        <Botao variante="secundario" onClick={() => setPagtos((xs) => [...xs, { contaId: '', valor: '', pago: true }])}>+ Forma de pagamento</Botao>
        <p className="mt-1 text-xs text-ink-muted">Itens: {formatarMoeda(totalItens)} · Pagamentos: {formatarMoeda(totalPagto)}{Math.abs(totalPagto - totalItens) > 0.01 && <span className="text-red-600"> — precisam bater</span>}</p>
      </div>
      <div className="flex justify-end gap-2">
        <Botao variante="secundario" onClick={aoFechar} disabled={salvando}>Cancelar</Botao>
        <Botao onClick={() => void salvar()} carregando={salvando}>Registrar compra</Botao>
      </div>
    </div>
  )
}

function MovimentacaoSimples({ item, aoFechar }: { item: EstoqueItem; aoFechar: () => void }) {
  const saida = useSaidaEstoque(); const ajuste = useAjusteEstoque(); const entrada = useEntradaEstoque()
  const pessoas = usePessoas()
  const [tipo, setTipo] = useState<'perda' | 'ajuste' | 'devolucao'>('ajuste')
  const [qtd, setQtd] = useState('')
  const [pessoaId, setPessoaId] = useState('')
  const [obs, setObs] = useState('')
  const erro = saida.error ?? ajuste.error ?? entrada.error
  const ocupado = saida.isPending || ajuste.isPending || entrada.isPending
  const v = Number(qtd.replace(',', '.'))
  function confirmar() {
    if (!(v >= 0)) return
    if (tipo === 'perda') saida.mutate({ item_id: item.id, quantidade: v, origem: 'perda', observacao: obs || null }, { onSuccess: aoFechar })
    if (tipo === 'ajuste') ajuste.mutate({ item_id: item.id, quantidade_nova: v, observacao: obs || null }, { onSuccess: aoFechar })
    if (tipo === 'devolucao') entrada.mutate({ item_id: item.id, quantidade: v, valor_total: Math.round(v * item.valor_custo * 100) / 100, origem: 'devolucao', observacao: obs || null }, { onSuccess: aoFechar })
  }
  return (
    <div className="space-y-4">
      {erro != null && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}
      <p className="text-sm"><b>{item.codigo} · {item.nome}</b> · atual: {fmtQtd(item.quantidade_atual)} {item.unidade_medida} · custo médio {formatarMoeda(item.valor_custo)}</p>
      <Selecao rotulo="Tipo" opcoes={[{ valor: 'ajuste', rotulo: 'Ajuste de inventário (define a quantidade)' }, { valor: 'perda', rotulo: 'Perda / baixa (saída)' }, { valor: 'devolucao', rotulo: 'Devolução (entrada pelo custo médio)' }]} value={tipo} onChange={(e) => setTipo(e.target.value as typeof tipo)} />
      <Campo rotulo={tipo === 'ajuste' ? `Quantidade REAL em estoque (${item.unidade_medida})` : `Quantidade (${item.unidade_medida})`} type="number" step="0.01" min="0" value={qtd} onChange={(e) => setQtd(e.target.value)} autoFocus />
      {tipo === 'devolucao' && (pessoas.data ?? []).length > 0 && (
        <Selecao rotulo="Cliente (opcional)" opcoes={[{ valor: '', rotulo: 'Nenhum' }, ...(pessoas.data ?? []).map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={pessoaId} onChange={(e) => setPessoaId(e.target.value)} />
      )}
      <Campo rotulo="Observação (opcional)" value={obs} onChange={(e) => setObs(e.target.value)} maxLength={300} />
      <div className="flex justify-end gap-2">
        <Botao variante="secundario" onClick={aoFechar} disabled={ocupado}>Cancelar</Botao>
        <Botao onClick={confirmar} carregando={ocupado} disabled={qtd.trim() === '' || Number.isNaN(v)}>Confirmar</Botao>
      </div>
    </div>
  )
}

export function EstoquePage() {
  const negocios = useNegocios()
  const itens = useEstoqueItens()
  const categorias = useEstoqueCategorias()
  const movs = useEstoqueMovs()
  const instalacoes = useInstalacoes()
  const consumoMensal = useConsumoMensal()
  const consumoItem = useConsumoItem()
  const pessoas = usePessoas()
  const salvarItem = useSalvarEstoqueItem()
  const salvarCategoria = useSalvarEstoqueCategoria()
  const [aba, setAba] = useState<Aba>('dashboard')
  const [negocioId, setNegocioId] = useState('')
  const [filtroStatus, setFiltroStatus] = useState('')
  const [modal, setModal] = useState<'item' | 'compra' | 'instalacao' | null>(null)
  const [itemEdicao, setItemEdicao] = useState<EstoqueItem | null>(null)
  const [itemMov, setItemMov] = useState<EstoqueItem | null>(null)
  const [novaCategoria, setNovaCategoria] = useState('')

  const servnet = (negocios.data ?? []).find((n) => n.nome.toLowerCase().includes('servnet')) ?? (negocios.data ?? [])[0]
  const negocioAtual = negocioId || servnet?.id || ''
  const lista = (itens.data ?? []).filter((i) => i.negocio_id === negocioAtual)
  const listaFiltrada = lista.filter((i) => !filtroStatus || statusItem(i).tom === filtroStatus)
  const nomeItem = useMemo(() => new Map((itens.data ?? []).map((i) => [i.id, `${i.codigo} · ${i.nome}`])), [itens.data])
  const nomeCategoria = useMemo(() => new Map((categorias.data ?? []).map((c) => [c.id, c.nome])), [categorias.data])
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const baixos = lista.filter((i) => i.ativo && statusItem(i).tom === 'baixo')
  const zerados = lista.filter((i) => i.ativo && statusItem(i).tom === 'zerado')
  const valorTotal = lista.reduce((s, i) => s + i.quantidade_atual * i.valor_custo, 0)
  const mesAtual = hojeISO().slice(0, 7)
  const consumoMes = (movs.data ?? []).filter((m) => m.tipo === 'saida' && m.data.startsWith(mesAtual)).reduce((s, m) => s + m.valor_total, 0)

  return (
    <>
      <CabecalhoPagina titulo="Estoque" descricao="Itens, movimentações e custo dos materiais"
        acoes={<span className="flex flex-wrap gap-2"><Botao variante="secundario" onClick={() => { setItemEdicao(null); setModal('item') }}>Novo item</Botao><Botao variante="secundario" onClick={() => setModal('compra')}>Nova compra</Botao><Botao onClick={() => setModal('instalacao')}>Nova instalação</Botao></span>} />

      {(baixos.length > 0 || zerados.length > 0) && (
        <div className="mb-4"><Alerta tipo="erro" titulo={`${zerados.length} item(ns) zerado(s) · ${baixos.length} abaixo do mínimo`}>
          {[...zerados, ...baixos].slice(0, 6).map((i) => `${i.codigo} (${fmtQtd(i.quantidade_atual)} ${i.unidade_medida})`).join(' · ')}
        </Alerta></div>
      )}

      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div role="tablist" className="flex gap-1 rounded-md border border-line p-1 text-sm">
          {(['dashboard', 'itens', 'movs', 'instalacoes', 'comodato', 'relatorios', 'categorias'] as Aba[]).map((a) => (
            <button key={a} role="tab" aria-selected={aba === a} onClick={() => setAba(a)} className={`rounded px-3 py-1.5 ${aba === a ? 'bg-brand-600 text-white' : 'text-ink-muted hover:text-ink'}`}>
              {a === 'dashboard' ? 'Dashboard' : a === 'itens' ? 'Itens' : a === 'movs' ? 'Movimentações' : a === 'instalacoes' ? 'Instalações' : a === 'comodato' ? 'Comodato' : a === 'relatorios' ? 'Relatórios' : 'Categorias'}
            </button>
          ))}
        </div>
        <select aria-label="Negócio" value={negocioAtual} onChange={(e) => setNegocioId(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
          {(negocios.data ?? []).filter((n) => n.ativo).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
        </select>
      </div>

      {itens.isPending && <Carregando />}

      {aba === 'dashboard' && itens.isSuccess && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">Itens cadastrados</p><p className="mt-1 text-xl font-semibold">{lista.length}</p></Cartao>
          <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">Estoque baixo / zerado</p><p className={`mt-1 text-xl font-semibold ${baixos.length + zerados.length > 0 ? 'text-red-700' : ''}`}>{baixos.length} / {zerados.length}</p></Cartao>
          <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">Valor do estoque</p><p className="mt-1 text-xl font-semibold tabular-nums">{formatarMoeda(valorTotal)}</p><p className="text-xs text-ink-muted">quantidade × custo médio</p></Cartao>
          <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">Consumo do mês</p><p className="mt-1 text-xl font-semibold tabular-nums">{formatarMoeda(consumoMes)}</p><p className="text-xs text-ink-muted">saídas (instalação + perda)</p></Cartao>
        </div>
      )}

      {aba === 'itens' && itens.isSuccess && (
        <Cartao className="p-0">
          <div className="flex items-center gap-3 border-b border-line px-4 py-3 text-sm">
            <select aria-label="Filtrar status" value={filtroStatus} onChange={(e) => setFiltroStatus(e.target.value)} className="h-9 rounded-md border border-line bg-white px-2">
              <option value="">Todos</option><option value="baixo">Baixo</option><option value="zerado">Zerado</option><option value="excesso">Excesso</option><option value="ok">Normal</option>
            </select>
            <span className="text-ink-muted">{listaFiltrada.length} item(ns)</span>
          </div>
          {listaFiltrada.length === 0 ? <p className="px-6 py-12 text-center text-sm text-ink-muted">Nenhum item. Clique em "Novo item" e depois lance a quantidade com Ajuste ou Compra.</p> : (
            <div className="overflow-x-auto"><table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Código</th><th className="px-4 py-2 font-medium">Item</th><th className="px-4 py-2 font-medium">Categoria</th><th className="px-4 py-2 text-right font-medium">Qtd.</th><th className="px-4 py-2 text-right font-medium">Custo médio</th><th className="px-4 py-2 text-right font-medium">Total</th><th className="px-4 py-2 font-medium">Status</th><th className="px-4 py-2"></th></tr></thead>
              <tbody>
                {listaFiltrada.map((i) => { const st = statusItem(i); return (
                  <tr key={i.id} className="border-b border-line last:border-0 hover:bg-surface">
                    <td className="px-4 py-2 font-mono text-xs">{i.codigo}</td>
                    <td className="px-4 py-2 font-medium">{i.nome}{!i.ativo && <span className="ml-2 text-xs text-ink-muted">(inativo)</span>}{(i.marca || i.modelo) && <span className="block text-xs font-normal text-ink-muted">{[i.marca, i.modelo].filter(Boolean).join(' · ')}</span>}</td>
                    <td className="px-4 py-2 text-ink-muted">{nomeCategoria.get(i.categoria_id) ?? '—'}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{fmtQtd(i.quantidade_atual)} {i.unidade_medida}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(i.valor_custo)}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(i.quantidade_atual * i.valor_custo)}</td>
                    <td className="px-4 py-2"><Distintivo tom={TOM_STATUS[st.tom]}>{st.rotulo}</Distintivo></td>
                    <td className="whitespace-nowrap px-4 py-2 text-right">
                      <button type="button" className="text-brand-700 hover:underline" onClick={() => setItemMov(i)}>Movimentar</button>
                      <button type="button" className="ml-3 text-brand-700 hover:underline" onClick={() => { setItemEdicao(i); setModal('item') }}>Editar</button>
                    </td>
                  </tr>
                ) })}
              </tbody>
            </table></div>
          )}
        </Cartao>
      )}

      {aba === 'movs' && (
        <Cartao className="p-0">
          {(movs.data ?? []).length === 0 ? <p className="px-6 py-12 text-center text-sm text-ink-muted">Sem movimentações ainda.</p> : (
            <div className="overflow-x-auto"><table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Data</th><th className="px-4 py-2 font-medium">Item</th><th className="px-4 py-2 font-medium">Origem</th><th className="px-4 py-2 text-right font-medium">Qtd.</th><th className="px-4 py-2 text-right font-medium">Valor</th><th className="px-4 py-2 font-medium">Obs.</th></tr></thead>
              <tbody>
                {(movs.data ?? []).map((m) => (
                  <tr key={m.id} className="border-b border-line last:border-0">
                    <td className="whitespace-nowrap px-4 py-2 tabular-nums">{formatarData(m.data)}</td>
                    <td className="px-4 py-2">{nomeItem.get(m.item_id) ?? '—'}</td>
                    <td className="px-4 py-2"><Distintivo tom={m.tipo === 'entrada' ? 'ok' : m.tipo === 'saida' ? 'alerta' : 'info'}>{ROTULO_ORIGEM[m.origem]}</Distintivo></td>
                    <td className={`px-4 py-2 text-right tabular-nums ${m.tipo === 'saida' || m.quantidade < 0 ? 'text-red-700' : 'text-green-700'}`}>{m.tipo === 'saida' ? '−' : m.quantidade < 0 ? '' : '+'}{fmtQtd(m.quantidade)}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(m.valor_total)}</td>
                    <td className="max-w-56 truncate px-4 py-2 text-xs text-ink-muted" title={m.observacao ?? ''}>{m.observacao ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table></div>
          )}
        </Cartao>
      )}

      {aba === 'instalacoes' && (
        <Cartao className="p-0">
          {(instalacoes.data ?? []).filter((x) => x.negocio_id === negocioAtual).length === 0 ? (
            <p className="px-6 py-12 text-center text-sm text-ink-muted">Nenhuma instalação registrada. Clique em "Nova instalação".</p>
          ) : (
            <div className="overflow-x-auto"><table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Data</th><th className="px-4 py-2 font-medium">Cliente</th><th className="px-4 py-2 text-right font-medium">Material</th><th className="px-4 py-2 text-right font-medium">Mão de obra</th><th className="px-4 py-2 text-right font-medium">Total</th><th className="px-4 py-2 font-medium">Técnico</th><th className="px-4 py-2 font-medium">Obs.</th></tr></thead>
              <tbody>
                {(instalacoes.data ?? []).filter((x) => x.negocio_id === negocioAtual).map((x) => (
                  <tr key={x.id} className="border-b border-line last:border-0">
                    <td className="whitespace-nowrap px-4 py-2 tabular-nums">{formatarData(x.data)}</td>
                    <td className="px-4 py-2 font-medium">{nomePessoa.get(x.pessoa_id) ?? '—'}{x.contrato_id ? '' : <span className="ml-2 text-xs font-normal text-ink-muted">(sem contrato)</span>}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(x.custo_material)}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(x.mao_de_obra)}</td>
                    <td className="px-4 py-2 text-right font-medium tabular-nums">{formatarMoeda(x.custo_total)}</td>
                    <td className="px-4 py-2 text-ink-muted">{x.tecnico ?? '—'}</td>
                    <td className="max-w-56 truncate px-4 py-2 text-xs text-ink-muted" title={x.observacao ?? ''}>{x.observacao ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table></div>
          )}
        </Cartao>
      )}

      {aba === 'relatorios' && (
        <div className="grid gap-6 lg:grid-cols-2">
          <Cartao className="p-0">
            <h2 className="border-b border-line px-6 py-3 text-sm font-semibold">Consumo por mês e origem</h2>
            {(consumoMensal.data ?? []).filter((c) => c.negocio_id === negocioAtual && c.tipo === 'saida').length === 0 ? (
              <p className="px-6 py-10 text-center text-sm text-ink-muted">Sem saídas registradas.</p>
            ) : (
              <table className="w-full text-sm"><thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Mês</th><th className="px-4 py-2 font-medium">Origem</th><th className="px-4 py-2 text-right font-medium">Movs.</th><th className="px-4 py-2 text-right font-medium">Valor</th></tr></thead>
                <tbody>
                  {(consumoMensal.data ?? []).filter((c) => c.negocio_id === negocioAtual && c.tipo === 'saida').map((c) => (
                    <tr key={`${c.mes}-${c.origem}`} className="border-b border-line last:border-0">
                      <td className="px-4 py-2 tabular-nums">{c.mes.split('-').reverse().join('/')}</td>
                      <td className="px-4 py-2">{ROTULO_ORIGEM[c.origem]}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{c.movimentacoes}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(c.valor_total)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </Cartao>
          <Cartao className="p-0">
            <h2 className="border-b border-line px-6 py-3 text-sm font-semibold">Itens mais consumidos (saídas por mês)</h2>
            {(consumoItem.data ?? []).filter((c) => c.negocio_id === negocioAtual).length === 0 ? (
              <p className="px-6 py-10 text-center text-sm text-ink-muted">Sem saídas registradas.</p>
            ) : (
              <table className="w-full text-sm"><thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Mês</th><th className="px-4 py-2 font-medium">Item</th><th className="px-4 py-2 text-right font-medium">Qtd.</th><th className="px-4 py-2 text-right font-medium">Valor</th></tr></thead>
                <tbody>
                  {(consumoItem.data ?? []).filter((c) => c.negocio_id === negocioAtual).map((c) => (
                    <tr key={`${c.mes}-${c.item_id}`} className="border-b border-line last:border-0">
                      <td className="px-4 py-2 tabular-nums">{c.mes.split('-').reverse().join('/')}</td>
                      <td className="px-4 py-2">{nomeItem.get(c.item_id) ?? '—'}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{fmtQtd(c.quantidade)}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(c.valor_total)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </Cartao>
        </div>
      )}

      {aba === 'comodato' && negocioAtual && <AbaComodato negocioId={negocioAtual} />}

      {aba === 'categorias' && (
        <Cartao className="p-4">
          <div className="mb-3 flex gap-2">
            <input value={novaCategoria} onChange={(e) => setNovaCategoria(e.target.value)} placeholder="Nova categoria…" className="h-10 flex-1 rounded-md border border-line bg-white px-3 text-sm" />
            <Botao carregando={salvarCategoria.isPending} disabled={novaCategoria.trim().length < 2} onClick={() => salvarCategoria.mutate({ negocio_id: negocioAtual, nome: novaCategoria.trim() }, { onSuccess: () => setNovaCategoria('') })}>Criar</Botao>
          </div>
          {salvarCategoria.error != null && <Alerta tipo="erro">{mensagemDeErro(salvarCategoria.error)}</Alerta>}
          <ul className="divide-y divide-line text-sm">
            {(categorias.data ?? []).filter((c) => c.negocio_id === negocioAtual).map((c) => (
              <li key={c.id} className="flex items-center justify-between py-2">
                <span className={c.ativo ? '' : 'text-ink-muted line-through'}>{c.nome}</span>
                <button type="button" className="text-xs text-brand-700 hover:underline" onClick={() => salvarCategoria.mutate({ id: c.id, negocio_id: c.negocio_id, nome: c.nome, ativo: !c.ativo })}>{c.ativo ? 'Desativar' : 'Reativar'}</button>
              </li>
            ))}
          </ul>
        </Cartao>
      )}

      <Modal aberto={modal === 'item'} aoFechar={() => { setModal(null); salvarItem.reset() }} largura="lg" titulo={itemEdicao ? 'Editar item' : 'Novo item'}>
        {modal === 'item' && negocioAtual && (
          <FormularioItem key={itemEdicao?.id ?? 'novo'} item={itemEdicao ?? undefined} negocioId={negocioAtual} salvando={salvarItem.isPending}
            erro={salvarItem.error ? mensagemDeErro(salvarItem.error) : null}
            aoSalvar={(d) => salvarItem.mutate(d, { onSuccess: () => { setModal(null); salvarItem.reset() } })}
            aoCancelar={() => { setModal(null); salvarItem.reset() }} />
        )}
      </Modal>

      <Modal aberto={modal === 'compra'} aoFechar={() => setModal(null)} largura="xl" titulo="Nova compra (entrada de estoque)">
        {modal === 'compra' && negocioAtual && <NovaCompra negocioId={negocioAtual} itens={lista} aoFechar={() => setModal(null)} />}
      </Modal>

      <Modal aberto={modal === 'instalacao'} aoFechar={() => setModal(null)} largura="xl" titulo="Nova instalação (materiais + mão de obra)">
        {modal === 'instalacao' && negocioAtual && <NovaInstalacao negocioId={negocioAtual} itens={lista} aoFechar={() => setModal(null)} />}
      </Modal>

      <Modal aberto={itemMov !== null} aoFechar={() => setItemMov(null)} largura="md" titulo="Movimentar item">
        {itemMov && <MovimentacaoSimples item={itemMov} aoFechar={() => setItemMov(null)} />}
      </Modal>
    </>
  )
}
