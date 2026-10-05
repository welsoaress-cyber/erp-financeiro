import { useMemo, useRef, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../../core/supabase/client'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { SelecaoBusca } from '../../../core/ui/SelecaoBusca'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarMoeda, hojeISO } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas, useCriarPessoa, useAtualizarPessoa } from '../../pessoas/api'
import { useContratos, useCriarContrato } from '../../contratos/api'
import { useCategorias, useCriarCategoria } from '../../categorias/api'
import { useContas } from '../../contas/api'
import { useEstoqueItens, useEstoqueCategorias, useSalvarEstoqueItem } from '../../estoque/api'
import { useEfetivarLancamento } from '../../lancamentos/api'
import { useRequisicoes, useRequisicaoItens, usePedidos, usePedidoItens, useCriarRequisicao, useAprovarRequisicao, useRegistrarRecebimento } from '../../compras/api'
import { codigoPedido } from '../../compras/tipos'
import { parseNFeXml } from '../parseNFe'
import type { NotaFiscalParseada } from '../tipos'
import { buscarNotaFiscalImportada, useRegistrarNotaFiscalImportada } from '../api'

type DestinoItem = 'estoque' | 'despesa' | 'servico'

interface LinhaItem {
  destino: DestinoItem
  itemEstoqueId: string
  categoriaFinanceiraId: string
  criandoItem: boolean
  novoCodigo: string
  novoEstoqueCategoriaId: string
  criandoCategoria: boolean
  novaCategoriaNome: string
}

const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
function sugerirItemEstoque(descricaoXml: string, itens: { id: string; nome: string }[]): string {
  const palavras = normalizar(descricaoXml).split(/\s+/).filter((p) => p.length >= 4)
  let melhor = { id: '', pontos: 0 }
  for (const it of itens) {
    const nomeNorm = normalizar(it.nome)
    const pontos = palavras.filter((p) => nomeNorm.includes(p)).length
    if (pontos > melhor.pontos) melhor = { id: it.id, pontos }
  }
  return melhor.pontos >= 2 ? melhor.id : ''
}

/** Assistente de importação de NFe (XML): fornecedor, requisição/pedido existente ou avulso,
 * material → estoque ou despesa/serviço, recorrência → contrato de fornecedor. Nada é gravado
 * sem revisão; o XML nunca fica guardado, só os dados que ele preenche na tela. */
export function ImportarNotaFiscal({ aoFechar }: { aoFechar: () => void }) {
  const [nota, setNota] = useState<NotaFiscalParseada | null>(null)
  const [erroArquivo, setErroArquivo] = useState<string | null>(null)
  const [duplicada, setDuplicada] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  async function aoEscolherArquivo(file: File) {
    setErroArquivo(null); setDuplicada(null)
    try {
      const texto = await file.text()
      const lida = parseNFeXml(texto)
      if (!lida.autorizada) { setErroArquivo(`Essa nota não está autorizada (${lida.situacao}) — não importo nota cancelada/rejeitada.`); return }
      const existente = await buscarNotaFiscalImportada(lida.chave)
      if (existente) { setDuplicada(`Essa nota já foi importada antes (chave ${lida.chave}).`); return }
      setNota(lida)
    } catch (e) {
      setErroArquivo(mensagemDeErro(e, 'Não consegui ler esse XML.'))
    }
  }

  if (!nota) {
    return (
      <div className="space-y-4">
        <p className="text-sm text-ink-muted">Escolha o arquivo XML da nota fiscal (procNFe/NFe). Nada é enviado pra fora — a leitura é só no seu navegador.</p>
        {erroArquivo && <Alerta tipo="erro">{erroArquivo}</Alerta>}
        {duplicada && <Alerta tipo="erro">{duplicada}</Alerta>}
        <input ref={inputRef} type="file" accept=".xml,text/xml" className="block w-full text-sm"
          onChange={(e) => { const f = e.target.files?.[0]; if (f) void aoEscolherArquivo(f) }} />
        <div className="flex justify-end"><Botao type="button" variante="secundario" onClick={aoFechar}>Cancelar</Botao></div>
      </div>
    )
  }

  return <Revisao nota={nota} aoReiniciar={() => setNota(null)} aoFechar={aoFechar} />
}

function Revisao({ nota, aoReiniciar, aoFechar }: { nota: NotaFiscalParseada; aoReiniciar: () => void; aoFechar: () => void }) {
  const negocios = useNegocios()
  const pessoas = usePessoas()
  const contratos = useContratos()
  const categorias = useCategorias()
  const contas = useContas()
  const estoqueItens = useEstoqueItens()
  const estoqueCategorias = useEstoqueCategorias()
  const requisicoes = useRequisicoes()
  const pedidos = usePedidos()

  const criarPessoa = useCriarPessoa()
  const atualizarPessoa = useAtualizarPessoa()
  const salvarItem = useSalvarEstoqueItem()
  const criarCategoria = useCriarCategoria()
  const criarRequisicao = useCriarRequisicao()
  const aprovarRequisicao = useAprovarRequisicao()
  const registrarRecebimento = useRegistrarRecebimento()
  const criarContrato = useCriarContrato()
  const efetivar = useEfetivarLancamento()
  const registrarNota = useRegistrarNotaFiscalImportada()

  const [negocioId, setNegocioId] = useState('')
  const cnpjNota = nota.fornecedorCnpj ?? nota.fornecedorCpf ?? ''
  const fornecedorExistente = useMemo(() => (pessoas.data ?? []).find((p) => p.documento === cnpjNota), [pessoas.data, cnpjNota])
  const [fornecedorIdEscolhido, setFornecedorIdEscolhido] = useState('')
  const fornecedorId = fornecedorIdEscolhido || fornecedorExistente?.id || ''
  const fornecedorNovoCriado = useMemo(() => (pessoas.data ?? []).find((p) => p.id === fornecedorIdEscolhido), [pessoas.data, fornecedorIdEscolhido])
  const [editandoFornecedor, setEditandoFornecedor] = useState(false)
  const [fornecedorNome, setFornecedorNome] = useState('')
  const [fornecedorEmail, setFornecedorEmail] = useState('')
  const [fornecedorTelefone, setFornecedorTelefone] = useState('')

  const [linhas, setLinhas] = useState<LinhaItem[]>(() => nota.itens.map(() => ({
    destino: 'despesa', itemEstoqueId: '', categoriaFinanceiraId: '', criandoItem: false, novoCodigo: '', novoEstoqueCategoriaId: '',
    criandoCategoria: false, novaCategoriaNome: '',
  })))
  // sugestão de item de estoque, roda quando a lista de itens do negócio muda
  const itensDoNegocio = (estoqueItens.data ?? []).filter((i) => i.ativo && i.negocio_id === negocioId)
  function linha(i: number) { return linhas[i] }
  function atualizarLinha(i: number, patch: Partial<LinhaItem>) {
    setLinhas((ls) => ls.map((l, idx) => idx === i ? { ...l, ...patch } : l))
  }
  function aplicarSugestoes() {
    setLinhas((ls) => ls.map((l, i) => {
      const sugestao = sugerirItemEstoque(nota.itens[i].descricao, itensDoNegocio.map((it) => ({ id: it.id, nome: it.nome })))
      return sugestao ? { ...l, destino: 'estoque', itemEstoqueId: sugestao } : l
    }))
  }

  const [recorrente, setRecorrente] = useState(false)
  const contratoExistente = useMemo(
    () => (contratos.data ?? []).find((c) => c.pessoa_id === fornecedorId && c.negocio_id === negocioId && c.tipo_financeiro === 'despesa' && c.status === 'ativo'),
    [contratos.data, fornecedorId, negocioId],
  )
  const [dia, setDia] = useState('10')
  const [periodicidade] = useState<'mensal'>('mensal')

  const faturaAberta = useQuery({
    queryKey: ['notas-fiscais', 'fatura-aberta', contratoExistente?.id ?? 'nenhum'],
    enabled: !!contratoExistente,
    queryFn: async () => {
      const { data, error } = await supabase.from('lancamentos').select('*').eq('contrato_id', contratoExistente!.id).eq('status', 'previsto').order('data_vencimento', { ascending: true }).limit(1).maybeSingle()
      if (error) throw error
      return data
    },
  })

  const requisicoesPendentes = (requisicoes.data ?? []).filter((r) => r.negocio_id === negocioId && r.status === 'pendente')
  const pedidosAbertos = (pedidos.data ?? []).filter((p) => p.negocio_id === negocioId && p.fornecedor_id === fornecedorId && (p.status === 'aberto' || p.status === 'recebido_parcial'))
  const [vinculo, setVinculo] = useState<{ tipo: 'nenhum' | 'requisicao' | 'pedido'; id: string }>({ tipo: 'nenhum', id: '' })
  const requisicaoEscolhidaItens = useRequisicaoItens(vinculo.tipo === 'requisicao' ? vinculo.id : null)
  const pedidoEscolhidoItens = usePedidoItens(vinculo.tipo === 'pedido' ? vinculo.id : null)

  const [contaId, setContaId] = useState('')
  const [pago, setPago] = useState(false)
  const [parcelas, setParcelas] = useState('1')
  const [enviando, setEnviando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  const categoriasDespesa = (categorias.data ?? []).filter((c) => c.tipo === 'despesa')

  async function confirmarFornecedorNovo() {
    const tipo = (cnpjNota.length === 14 ? 'juridica' : 'fisica') as 'juridica' | 'fisica'
    const criado = await criarPessoa.mutateAsync({
      tipo, nome: nota.fornecedorNome || 'Fornecedor', documento: cnpjNota || null,
      email: null, telefone: null, data_nascimento: null, observacao: null, ativo: true, receber_avisos: false,
    })
    setFornecedorIdEscolhido(criado.id)
    setFornecedorNome(criado.nome)
    setFornecedorEmail(criado.email ?? '')
    setFornecedorTelefone(criado.telefone ?? '')
  }

  async function salvarEdicaoFornecedor() {
    if (!fornecedorNovoCriado) return
    await atualizarPessoa.mutateAsync({
      id: fornecedorNovoCriado.id, tipo: fornecedorNovoCriado.tipo, nome: fornecedorNome.trim(), documento: fornecedorNovoCriado.documento,
      email: fornecedorEmail.trim() || null, telefone: fornecedorTelefone.trim() || null,
      data_nascimento: null, observacao: fornecedorNovoCriado.observacao, ativo: true, receber_avisos: false,
    })
    setEditandoFornecedor(false)
  }

  async function criarCategoriaInline(i: number) {
    const l = linha(i)
    if (!l.novaCategoriaNome.trim()) return
    const nova = await criarCategoria.mutateAsync({ nome: l.novaCategoriaNome.trim(), tipo: 'despesa', categoria_pai_id: null, natureza: 'operacional', ativo: true })
    atualizarLinha(i, { categoriaFinanceiraId: nova.id, criandoCategoria: false })
  }

  async function criarItemInline(i: number) {
    const l = linha(i)
    if (!l.novoCodigo.trim() || !l.novoEstoqueCategoriaId) return
    const novo = await salvarItem.mutateAsync({
      negocio_id: negocioId, categoria_id: l.novoEstoqueCategoriaId, codigo: l.novoCodigo.trim(),
      nome: nota.itens[i].descricao, descricao: null, unidade_medida: 'unidade', marca: null, modelo: null,
      valor_venda: null, quantidade_minima: 0, quantidade_maxima: null, localizacao: null, ativo: true,
    })
    atualizarLinha(i, { itemEstoqueId: novo.id, criandoItem: false })
  }

  function validar(): string | null {
    if (!negocioId) return 'Escolha o negócio.'
    if (!fornecedorId) return 'Escolha ou cadastre o fornecedor.'
    if (!recorrente) {
      for (let i = 0; i < linhas.length; i++) {
        const l = linhas[i]
        if (l.destino === 'estoque' && !l.itemEstoqueId) return `Item "${nota.itens[i].descricao}": escolha ou cadastre o item de estoque.`
        if (l.destino !== 'estoque' && !l.categoriaFinanceiraId) return `Item "${nota.itens[i].descricao}": escolha a categoria de despesa.`
      }
      if (!contaId) return 'Escolha a conta.'
    } else if (!contratoExistente && !contaId) {
      return 'Escolha a conta.'
    }
    return null
  }

  async function importar() {
    const msg = validar()
    if (msg) { setErro(msg); return }
    setErro(null); setEnviando(true)
    try {
      if (recorrente) {
        if (contratoExistente) {
          // 2ª nota em diante: casa com a fatura que o contrato já gerou e só dá baixa
          const fatura = faturaAberta.data
          if (!fatura) throw new Error('Esse contrato não tem fatura em aberto pra dar baixa agora.')
          const lanc = await efetivar.mutateAsync({ id: fatura.id, data_efetivacao: hojeISO(), conta_id: contaId || undefined })
          await registrarNota.mutateAsync({
            negocio_id: negocioId, fornecedor_id: fornecedorId, chave: nota.chave, numero: nota.numero || null,
            valor: nota.valorTotal, emitida_em: nota.dataEmissao, destino: 'contrato', contrato_id: contratoExistente.id, lancamento_id: lanc.id,
          })
        } else {
          // 1ª nota: cria o contrato de fornecedor recorrente
          const novoContrato = await criarContrato.mutateAsync({
            negocio_id: negocioId, pessoa_id: fornecedorId, plano_id: '', valor: nota.valorTotal, periodicidade,
            data_inicio: hojeISO(), dia_vencimento: Number(dia) || 10, observacao: `Criado a partir da nota ${nota.numero} (importação XML).`,
            faturar_desde: hojeISO(), conta_id: contaId || null, tipo_financeiro: 'despesa', cortesia: false, centro_custo_id: null,
          })
          await registrarNota.mutateAsync({
            negocio_id: negocioId, fornecedor_id: fornecedorId, chave: nota.chave, numero: nota.numero || null,
            valor: nota.valorTotal, emitida_em: nota.dataEmissao, destino: 'contrato', contrato_id: novoContrato.id,
          })
        }
      } else {
        let pedidoId = vinculo.tipo === 'pedido' ? vinculo.id : ''
        let itensRecebimento: { compra_item_id: string; quantidade: number }[] = []

        if (vinculo.tipo === 'pedido' && pedidoEscolhidoItens.data) {
          itensRecebimento = pedidoEscolhidoItens.data.map((pi) => ({ compra_item_id: pi.id, quantidade: pi.quantidade - pi.quantidade_recebida }))
        } else {
          // requisição pendente (aprova junto) ou avulso (cria requisição + aprova na hora)
          let reqId = vinculo.tipo === 'requisicao' ? vinculo.id : ''
          let itensOrdem = vinculo.tipo === 'requisicao' ? (requisicaoEscolhidaItens.data ?? []) : null
          if (!reqId) {
            const nova = await criarRequisicao.mutateAsync({
              negocio_id: negocioId,
              itens: nota.itens.map((it, i) => ({ descricao: it.descricao, quantidade: it.quantidade, destino: linhas[i].destino === 'estoque' ? 'estoque' : (linhas[i].destino === 'servico' ? 'servico' : 'despesa'), item_id: linhas[i].itemEstoqueId || null })),
              justificativa: `Importada da nota ${nota.numero} (XML).`,
            })
            reqId = nova.id
            const { data: itensNovos } = await supabase.from('compra_requisicao_itens').select('*').eq('requisicao_id', reqId).order('ordem')
            itensOrdem = itensNovos ?? []
          }
          const valores = (itensOrdem ?? []).map((_, i) => ({
            valor_unitario: nota.itens[i]?.valorUnitario ?? 0,
            categoria_id: linhas[i]?.categoriaFinanceiraId || null,
          }))
          const pedido = await aprovarRequisicao.mutateAsync({ id: reqId, fornecedor_id: fornecedorId, valores, data_pedido: hojeISO() })
          pedidoId = pedido.id
          const { data: itensPedido } = await supabase.from('compra_itens').select('*').eq('compra_id', pedidoId)
          itensRecebimento = (itensPedido ?? []).map((pi) => ({ compra_item_id: pi.id, quantidade: Number(pi.quantidade) }))
        }

        const receb = await registrarRecebimento.mutateAsync({
          compra_id: pedidoId, itens: itensRecebimento, data: hojeISO(),
          nota_numero: nota.numero || null, nota_chave: nota.chave, nota_valor: nota.valorTotal,
          conta_id: contaId, pago, parcelas: Number(parcelas) || 1,
        })
        await registrarNota.mutateAsync({
          negocio_id: negocioId, fornecedor_id: fornecedorId, chave: nota.chave, numero: nota.numero || null,
          valor: nota.valorTotal, emitida_em: nota.dataEmissao, destino: 'compra', compra_id: pedidoId, lancamento_id: receb.lancamento_id,
        })
      }
      aoFechar()
    } catch (e) {
      setErro(mensagemDeErro(e))
    } finally {
      setEnviando(false)
    }
  }

  const carregando = negocios.isPending || pessoas.isPending || contratos.isPending || categorias.isPending || contas.isPending
  if (carregando) return <Carregando />

  return (
    <div className="space-y-5">
      <div className="rounded-md border border-line bg-surface/60 p-3 text-sm">
        <p><b>NF {nota.numero}</b> · {nota.fornecedorNome} · {formatarMoeda(nota.valorTotal)} · {nota.itens.length} item(ns)</p>
        <p className="text-xs text-ink-muted">Chave {nota.chave}</p>
      </div>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}

      <Selecao rotulo="Negócio" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(negocios.data ?? []).filter((n) => n.ativo).map((n) => ({ valor: n.id, rotulo: n.nome }))]} value={negocioId} onChange={(e) => setNegocioId(e.target.value)} />

      <div>
        <p className="mb-1 text-sm font-medium text-ink">Fornecedor</p>
        {fornecedorExistente && !fornecedorIdEscolhido ? (
          <p className="text-sm">✓ <b>{fornecedorExistente.nome}</b> (CNPJ já cadastrado)</p>
        ) : fornecedorIdEscolhido && fornecedorNovoCriado ? (
          <div className="space-y-2">
            <p className="text-sm text-green-700">✓ Fornecedor cadastrado agora: <b>{fornecedorNovoCriado.nome}</b>.{' '}
              {!editandoFornecedor && <button type="button" className="font-medium text-brand-600 hover:underline" onClick={() => setEditandoFornecedor(true)}>Editar</button>}
            </p>
            {editandoFornecedor && (
              <div className="space-y-2 rounded-md border border-line bg-canvas p-3">
                {atualizarPessoa.error && <Alerta tipo="erro">{mensagemDeErro(atualizarPessoa.error)}</Alerta>}
                <Campo rotulo="Nome" value={fornecedorNome} onChange={(e) => setFornecedorNome(e.target.value)} />
                <div className="grid grid-cols-2 gap-2">
                  <Campo rotulo="E-mail (opcional)" type="email" value={fornecedorEmail} onChange={(e) => setFornecedorEmail(e.target.value)} />
                  <Campo rotulo="Telefone (opcional)" value={fornecedorTelefone} onChange={(e) => setFornecedorTelefone(e.target.value)} />
                </div>
                <div className="flex justify-end gap-2">
                  <Botao type="button" variante="secundario" onClick={() => setEditandoFornecedor(false)}>Cancelar</Botao>
                  <Botao type="button" carregando={atualizarPessoa.isPending} onClick={() => void salvarEdicaoFornecedor()}>Salvar</Botao>
                </div>
              </div>
            )}
          </div>
        ) : (
          <div className="space-y-2 rounded-md border border-amber-200 bg-amber-50 p-3">
            <p className="text-sm">Não achei nenhum fornecedor com o CNPJ {cnpjNota || '(não veio no XML)'}.</p>
            <p className="text-sm">Nome na nota: <b>{nota.fornecedorNome}</b></p>
            <Botao type="button" carregando={criarPessoa.isPending} onClick={() => void confirmarFornecedorNovo()}>Cadastrar fornecedor</Botao>
          </div>
        )}
      </div>

      {negocioId && fornecedorId && (
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={recorrente} onChange={(e) => setRecorrente(e.target.checked)} />
          <span>Essa nota é recorrente (vira/já é um contrato de fornecedor).</span>
        </label>
      )}

      {negocioId && fornecedorId && !recorrente && (
        <>
          <div>
            <div className="mb-2 flex items-center justify-between">
              <p className="text-sm font-medium text-ink">Itens</p>
              <button type="button" className="text-xs font-medium text-brand-600 hover:underline" onClick={aplicarSugestoes}>Tentar casar com o estoque</button>
            </div>
            <ul className="space-y-3">
              {nota.itens.map((it, i) => {
                const l = linhas[i]
                return (
                  <li key={i} className="rounded-md border border-line p-3">
                    <p className="text-sm font-medium">{it.descricao}</p>
                    <p className="text-xs text-ink-muted">{it.quantidade} {it.unidade} × {formatarMoeda(it.valorUnitario)} = {formatarMoeda(it.valorTotal)}</p>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {(['estoque', 'despesa', 'servico'] as DestinoItem[]).map((d) => (
                        <button key={d} type="button" onClick={() => atualizarLinha(i, { destino: d })}
                          className={`rounded px-2 py-1 text-xs font-medium ${l.destino === d ? 'bg-brand-600 text-white' : 'border border-line text-ink-muted'}`}>
                          {d === 'estoque' ? 'Material (estoque)' : d === 'despesa' ? 'Despesa' : 'Serviço'}
                        </button>
                      ))}
                    </div>
                    {l.destino === 'estoque' ? (
                      <div className="mt-2 space-y-2">
                        <SelecaoBusca rotulo="Item do estoque" opcoes={itensDoNegocio.map((x) => ({ valor: x.id, rotulo: `${x.codigo} · ${x.nome}` }))}
                          value={l.itemEstoqueId} onChange={(v) => atualizarLinha(i, { itemEstoqueId: v })} placeholder="Buscar item…" />
                        {!l.itemEstoqueId && (
                          l.criandoItem ? (
                            <div className="space-y-2 rounded-md bg-canvas p-2">
                              <Selecao rotulo="Categoria do estoque" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(estoqueCategorias.data ?? []).filter((c) => c.negocio_id === negocioId).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={l.novoEstoqueCategoriaId} onChange={(e) => atualizarLinha(i, { novoEstoqueCategoriaId: e.target.value })} />
                              <Campo rotulo="Código do item" value={l.novoCodigo} onChange={(e) => atualizarLinha(i, { novoCodigo: e.target.value })} />
                              <Botao type="button" carregando={salvarItem.isPending} onClick={() => void criarItemInline(i)}>Cadastrar item</Botao>
                            </div>
                          ) : (
                            <button type="button" className="text-xs font-medium text-brand-600 hover:underline" onClick={() => atualizarLinha(i, { criandoItem: true })}>Não achei — cadastrar item novo</button>
                          )
                        )}
                      </div>
                    ) : (
                      <div className="mt-2 space-y-2">
                        <Selecao rotulo="Categoria de despesa" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...categoriasDespesa.map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={l.categoriaFinanceiraId} onChange={(e) => atualizarLinha(i, { categoriaFinanceiraId: e.target.value })} />
                        {l.criandoCategoria ? (
                          <div className="flex items-end gap-2 rounded-md bg-canvas p-2">
                            <div className="flex-1"><Campo rotulo="Nome da categoria nova" value={l.novaCategoriaNome} onChange={(e) => atualizarLinha(i, { novaCategoriaNome: e.target.value })} /></div>
                            <Botao type="button" variante="secundario" onClick={() => atualizarLinha(i, { criandoCategoria: false })}>Cancelar</Botao>
                            <Botao type="button" carregando={criarCategoria.isPending} onClick={() => void criarCategoriaInline(i)}>Criar</Botao>
                          </div>
                        ) : (
                          <button type="button" className="text-xs font-medium text-brand-600 hover:underline" onClick={() => atualizarLinha(i, { criandoCategoria: true })}>+ Nova categoria</button>
                        )}
                      </div>
                    )}
                  </li>
                )
              })}
            </ul>
          </div>

          <div>
            <p className="mb-1 text-sm font-medium text-ink">Já tem requisição ou pedido pra esse fornecedor?</p>
            <div className="space-y-1">
              <label className="flex items-center gap-2 text-sm"><input type="radio" checked={vinculo.tipo === 'nenhum'} onChange={() => setVinculo({ tipo: 'nenhum', id: '' })} /> Nenhum — é uma compra nova</label>
              {pedidosAbertos.map((p) => (
                <label key={p.id} className="flex items-center gap-2 text-sm"><input type="radio" checked={vinculo.tipo === 'pedido' && vinculo.id === p.id} onChange={() => setVinculo({ tipo: 'pedido', id: p.id })} /> Pedido {codigoPedido(p)} em aberto</label>
              ))}
              {requisicoesPendentes.map((r) => (
                <label key={r.id} className="flex items-center gap-2 text-sm"><input type="radio" checked={vinculo.tipo === 'requisicao' && vinculo.id === r.id} onChange={() => setVinculo({ tipo: 'requisicao', id: r.id })} /> Requisição REQ-{String(r.numero).padStart(4, '0')} pendente{r.justificativa ? ` — ${r.justificativa}` : ''}</label>
              ))}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
            <Selecao rotulo="Conta" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(contas.data ?? []).filter((c) => c.ativo).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} />
            <Campo rotulo="Parcelas" type="number" min={1} value={parcelas} onChange={(e) => setParcelas(e.target.value)} />
            <label className="flex items-center gap-2 pt-6 text-sm"><input type="checkbox" checked={pago} onChange={(e) => setPago(e.target.checked)} /> Já paguei</label>
          </div>
        </>
      )}

      {negocioId && fornecedorId && recorrente && (
        contratoExistente ? (
          faturaAberta.isPending ? <Carregando /> : faturaAberta.data ? (
            <div className="space-y-3 rounded-md border border-line p-3">
              <p className="text-sm">Contrato de fornecedor já existe. Fatura em aberto: <b>{formatarMoeda(Number(faturaAberta.data.valor))}</b> venc. {faturaAberta.data.data_vencimento}.</p>
              {Number(faturaAberta.data.valor) !== nota.valorTotal && (
                <Alerta tipo="info">O valor da fatura ({formatarMoeda(Number(faturaAberta.data.valor))}) é diferente do valor da nota ({formatarMoeda(nota.valorTotal)}). Confere antes de dar baixa.</Alerta>
              )}
              <Selecao rotulo="Conta" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(contas.data ?? []).filter((c) => c.ativo).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} />
            </div>
          ) : (
            <Alerta tipo="info">Esse contrato não tem fatura prevista em aberto agora — nada pra dar baixa.</Alerta>
          )
        ) : (
          <div className="space-y-3 rounded-md border border-line p-3">
            <p className="text-sm">Primeira nota desse fornecedor recorrente — vou criar um contrato de fornecedor (despesa mensal, valor {formatarMoeda(nota.valorTotal)}).</p>
            <Campo rotulo="Dia de vencimento" type="number" min={1} max={31} value={dia} onChange={(e) => setDia(e.target.value)} />
            <Selecao rotulo="Conta de pagamento" opcoes={[{ valor: '', rotulo: 'Padrão do negócio' }, ...(contas.data ?? []).filter((c) => c.ativo).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} />
          </div>
        )
      )}

      <div className="flex justify-between gap-2 border-t border-line pt-3">
        <Botao type="button" variante="secundario" onClick={aoReiniciar}>Trocar arquivo</Botao>
        <div className="flex gap-2">
          <Botao type="button" variante="secundario" onClick={aoFechar}>Cancelar</Botao>
          <Botao type="button" carregando={enviando} disabled={!negocioId || !fornecedorId} onClick={() => void importar()}>Importar</Botao>
        </div>
      </div>
    </div>
  )
}
