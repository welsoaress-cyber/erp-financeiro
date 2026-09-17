import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { Selecao } from '../../../core/ui/Selecao'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { Carregando } from '../../../core/ui/Carregando'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda, hojeISO } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useCategorias } from '../../categorias/api'
import { useEstoqueItens } from '../../estoque/api'
import {
  useAprovarRequisicao, useCancelarPedido, useCancelarRequisicao, useCriarRequisicao,
  usePedidoItens, usePedidos, useRejeitarRequisicao, useRequisicaoItens, useRequisicoes, useTotaisPedido,
} from '../api'
import { codigoPedido, codigoRequisicao, ROTULO_DESTINO, ROTULO_STATUS_PEDIDO, ROTULO_STATUS_REQ, type DestinoCompra, type Requisicao, type Pedido } from '../tipos'

type Aba = 'requisicoes' | 'pedidos'

const TOM_REQ = { pendente: 'alerta', aprovada: 'ok', rejeitada: 'alerta', convertida: 'ok', cancelada: 'neutro' } as const
const TOM_PED = { aberto: 'alerta', recebido_parcial: 'info', recebido: 'ok', cancelado: 'neutro' } as const
const DESTINOS: DestinoCompra[] = ['estoque', 'despesa', 'patrimonio', 'comodato', 'servico']

interface LinhaReq { descricao: string; quantidade: string; destino: DestinoCompra; item_id: string; observacao: string }

function FormularioRequisicao({ negocioId, aoFechar }: { negocioId: string; aoFechar: () => void }) {
  const criar = useCriarRequisicao()
  const itens = useEstoqueItens()
  const [justificativa, setJustificativa] = useState('')
  const [linhas, setLinhas] = useState<LinhaReq[]>([{ descricao: '', quantidade: '', destino: 'estoque', item_id: '', observacao: '' }])
  const [erro, setErro] = useState<string | null>(null)
  const itensNegocio = (itens.data ?? []).filter((i) => i.negocio_id === negocioId && i.ativo)

  async function salvar() {
    setErro(null)
    const ok = linhas.map((l) => ({ ...l, q: Number(l.quantidade.replace(',', '.')) })).filter((l) => l.descricao.trim().length >= 2 && l.q > 0)
    if (ok.length === 0) { setErro('Adicione ao menos um item com descrição e quantidade.'); return }
    try {
      await criar.mutateAsync({
        negocio_id: negocioId,
        justificativa: justificativa.trim() || null,
        itens: ok.map((l) => ({ descricao: l.descricao.trim(), quantidade: l.q, destino: l.destino, item_id: l.item_id || null, observacao: l.observacao.trim() || null })),
      })
      aoFechar()
    } catch (e) { setErro(mensagemDeErro(e)) }
  }

  return (
    <div className="space-y-4">
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <AreaTexto rotulo="Justificativa (opcional)" rows={2} maxLength={500} value={justificativa} onChange={(e) => setJustificativa(e.target.value)} placeholder="Ex.: reposição de cabo drop, estoque em nível crítico" />
      <div>
        <p className="mb-1 text-sm font-medium">Itens solicitados (sem valor — o valor entra na aprovação)</p>
        {linhas.map((l, i) => (
          <div key={i} className="mb-2 grid grid-cols-12 items-end gap-2">
            <div className="col-span-5"><Selecao rotulo={i === 0 ? 'Item do estoque (opcional)' : ''} opcoes={[{ valor: '', rotulo: 'Livre (descrever abaixo)…' }, ...itensNegocio.map((x) => ({ valor: x.id, rotulo: `${x.codigo} · ${x.nome}` }))]} value={l.item_id} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, item_id: e.target.value, descricao: e.target.value ? (itensNegocio.find((y) => y.id === e.target.value)?.nome ?? x.descricao) : x.descricao } : x)))} /></div>
            <input aria-label="Descrição" className="col-span-4 h-10 rounded-md border border-line bg-white px-2 text-sm" placeholder="Descrição" value={l.descricao} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, descricao: e.target.value } : x)))} />
            <input aria-label="Quantidade" className="col-span-1 h-10 rounded-md border border-line bg-white px-2 text-sm" type="number" step="0.01" min="0.01" placeholder="Qtd" value={l.quantidade} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, quantidade: e.target.value } : x)))} />
            <select aria-label="Destino" className="col-span-1 h-10 rounded-md border border-line bg-white px-2 text-sm" value={l.destino} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, destino: e.target.value as DestinoCompra } : x)))}>
              {DESTINOS.map((d) => <option key={d} value={d}>{ROTULO_DESTINO[d]}</option>)}
            </select>
            <button type="button" aria-label="Remover" className="col-span-1 pb-2 text-ink-muted hover:text-red-700" onClick={() => setLinhas((xs) => xs.filter((_, j) => j !== i))}>×</button>
          </div>
        ))}
        <Botao variante="secundario" onClick={() => setLinhas((xs) => [...xs, { descricao: '', quantidade: '', destino: 'estoque', item_id: '', observacao: '' }])}>+ Item</Botao>
      </div>
      <p className="text-xs text-ink-muted">A requisição nasce pendente. Só o proprietário aprova (converte em pedido) ou rejeita.</p>
      <div className="flex justify-end gap-2">
        <Botao variante="secundario" onClick={aoFechar} disabled={criar.isPending}>Cancelar</Botao>
        <Botao onClick={() => void salvar()} carregando={criar.isPending}>Registrar requisição</Botao>
      </div>
    </div>
  )
}

function DetalheRequisicao({ req, aoFechar }: { req: Requisicao; aoFechar: () => void }) {
  const itens = useRequisicaoItens(req.id)
  const pessoas = usePessoas()
  const categorias = useCategorias()
  const aprovar = useAprovarRequisicao()
  const rejeitar = useRejeitarRequisicao()
  const cancelar = useCancelarRequisicao()
  const [modo, setModo] = useState<'ver' | 'aprovar' | 'rejeitar'>('ver')
  const [fornecedorId, setFornecedorId] = useState('')
  const [dataPedido, setDataPedido] = useState(hojeISO())
  const [previsao, setPrevisao] = useState('')
  const [condicao, setCondicao] = useState('')
  const [frete, setFrete] = useState('')
  const [desconto, setDesconto] = useState('')
  const [observacao, setObservacao] = useState('')
  const [motivo, setMotivo] = useState('')
  const [valores, setValores] = useState<Record<string, { valor: string; categoria: string; contrato: string }>>({})
  const [erro, setErro] = useState<string | null>(null)
  const catsDespesa = (categorias.data ?? []).filter((c) => c.tipo === 'despesa' && c.ativo)

  const totalCalculado = useMemo(() => {
    const lista = itens.data ?? []
    let s = 0
    for (const it of lista) {
      const v = Number((valores[it.id]?.valor ?? '').replace(',', '.')) || 0
      s += v * it.quantidade
    }
    return s + (Number(frete.replace(',', '.')) || 0) - (Number(desconto.replace(',', '.')) || 0)
  }, [valores, itens.data, frete, desconto])

  async function aprovarAgora() {
    setErro(null)
    if (!fornecedorId) { setErro('Escolha o fornecedor.'); return }
    const lista = itens.data ?? []
    const valoresArr = lista.map((it) => ({
      valor_unitario: Number((valores[it.id]?.valor ?? '').replace(',', '.')) || 0,
      categoria_id: valores[it.id]?.categoria || null,
      contrato_id: valores[it.id]?.contrato || null,
    }))
    if (valoresArr.some((v) => v.valor_unitario < 0)) { setErro('Valores unitários não podem ser negativos.'); return }
    try {
      await aprovar.mutateAsync({
        id: req.id, fornecedor_id: fornecedorId, valores: valoresArr,
        data_pedido: dataPedido, previsao_entrega: previsao || null,
        condicao_pagamento: condicao.trim() || null,
        valor_frete: Math.round((Number(frete.replace(',', '.')) || 0) * 100) / 100,
        valor_desconto: Math.round((Number(desconto.replace(',', '.')) || 0) * 100) / 100,
        observacao: observacao.trim() || null,
      })
      aoFechar()
    } catch (e) { setErro(mensagemDeErro(e)) }
  }

  async function rejeitarAgora() {
    setErro(null)
    if (motivo.trim().length < 3) { setErro('Informe o motivo (mínimo 3 caracteres).'); return }
    try { await rejeitar.mutateAsync({ id: req.id, motivo: motivo.trim() }); aoFechar() } catch (e) { setErro(mensagemDeErro(e)) }
  }

  return (
    <div className="space-y-4">
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <div className="flex items-baseline justify-between text-sm">
        <p><b>{codigoRequisicao(req)}</b> · {formatarData(req.criado_em)} · <Distintivo tom={TOM_REQ[req.status]}>{ROTULO_STATUS_REQ[req.status]}</Distintivo></p>
        {req.motivo_rejeicao && <span className="text-xs text-red-700">Motivo: {req.motivo_rejeicao}</span>}
      </div>
      {req.justificativa && <p className="rounded-md border border-line bg-surface/60 p-2 text-sm">{req.justificativa}</p>}
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-3 py-2 font-medium">Item</th><th className="px-3 py-2 font-medium">Destino</th><th className="px-3 py-2 text-right font-medium">Qtd</th>{modo === 'aprovar' && <><th className="px-3 py-2 text-right font-medium">Valor unit.</th><th className="px-3 py-2 font-medium">Categoria</th></>}</tr></thead>
          <tbody>
            {(itens.data ?? []).map((i) => (
              <tr key={i.id} className="border-b border-line last:border-0">
                <td className="px-3 py-2">{i.descricao}{i.observacao && <span className="block text-xs text-ink-muted">{i.observacao}</span>}</td>
                <td className="px-3 py-2 text-xs">{ROTULO_DESTINO[i.destino]}</td>
                <td className="px-3 py-2 text-right tabular-nums">{i.quantidade}</td>
                {modo === 'aprovar' && (
                  <>
                    <td className="px-3 py-2"><input type="number" step="0.01" min="0" className="h-9 w-28 rounded-md border border-line bg-white px-2 text-right text-sm" value={valores[i.id]?.valor ?? ''} onChange={(e) => setValores((v) => ({ ...v, [i.id]: { ...(v[i.id] ?? { valor: '', categoria: '', contrato: '' }), valor: e.target.value } }))} /></td>
                    <td className="px-3 py-2"><select className="h-9 w-40 rounded-md border border-line bg-white px-2 text-sm" value={valores[i.id]?.categoria ?? ''} onChange={(e) => setValores((v) => ({ ...v, [i.id]: { ...(v[i.id] ?? { valor: '', categoria: '', contrato: '' }), categoria: e.target.value } }))}><option value="">Padrão do negócio</option>{catsDespesa.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}</select></td>
                  </>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {modo === 'aprovar' && (
        <div className="space-y-3 rounded-md border border-line bg-surface/60 p-3">
          <div className="grid grid-cols-2 gap-3">
            <Selecao rotulo="Fornecedor" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(pessoas.data ?? []).map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={fornecedorId} onChange={(e) => setFornecedorId(e.target.value)} />
            <Campo rotulo="Data do pedido" type="date" value={dataPedido} onChange={(e) => setDataPedido(e.target.value)} />
          </div>
          <div className="grid grid-cols-3 gap-3">
            <Campo rotulo="Previsão de entrega" type="date" value={previsao} onChange={(e) => setPrevisao(e.target.value)} />
            <Campo rotulo="Condição de pagamento" value={condicao} onChange={(e) => setCondicao(e.target.value)} maxLength={60} placeholder="Ex.: 30 dias" />
            <div />
          </div>
          <div className="grid grid-cols-3 gap-3">
            <Campo rotulo="Frete (R$)" type="number" step="0.01" min="0" value={frete} onChange={(e) => setFrete(e.target.value)} />
            <Campo rotulo="Desconto (R$)" type="number" step="0.01" min="0" value={desconto} onChange={(e) => setDesconto(e.target.value)} />
            <div className="flex items-end"><p className="text-sm text-ink-muted">Total do pedido: <b className="text-ink">{formatarMoeda(totalCalculado)}</b></p></div>
          </div>
          <Campo rotulo="Observação (opcional)" value={observacao} onChange={(e) => setObservacao(e.target.value)} maxLength={300} />
        </div>
      )}

      {modo === 'rejeitar' && (
        <AreaTexto rotulo="Motivo da rejeição" rows={2} maxLength={300} value={motivo} onChange={(e) => setMotivo(e.target.value)} />
      )}

      <div className="flex justify-end gap-2 border-t border-line pt-3">
        {req.status === 'pendente' && modo === 'ver' && (
          <>
            <Botao variante="secundario" onClick={() => cancelar.mutate(req.id, { onSuccess: aoFechar })} carregando={cancelar.isPending}>Cancelar requisição</Botao>
            <Botao variante="perigo" onClick={() => setModo('rejeitar')}>Rejeitar</Botao>
            <Botao onClick={() => setModo('aprovar')}>Aprovar e gerar pedido</Botao>
          </>
        )}
        {modo === 'aprovar' && <>
          <Botao variante="secundario" onClick={() => setModo('ver')}>Voltar</Botao>
          <Botao onClick={() => void aprovarAgora()} carregando={aprovar.isPending}>Confirmar aprovação</Botao>
        </>}
        {modo === 'rejeitar' && <>
          <Botao variante="secundario" onClick={() => setModo('ver')}>Voltar</Botao>
          <Botao variante="perigo" onClick={() => void rejeitarAgora()} carregando={rejeitar.isPending}>Confirmar rejeição</Botao>
        </>}
        {req.status !== 'pendente' && modo === 'ver' && <Botao variante="secundario" onClick={aoFechar}>Fechar</Botao>}
      </div>
    </div>
  )
}

function DetalhePedido({ ped, aoFechar }: { ped: Pedido; aoFechar: () => void }) {
  const itens = usePedidoItens(ped.id)
  const totais = useTotaisPedido(ped.id)
  const pessoas = usePessoas()
  const cancelar = useCancelarPedido()
  const fornecedor = (pessoas.data ?? []).find((p) => p.id === ped.fornecedor_id)?.nome ?? '—'
  return (
    <div className="space-y-4">
      <div className="flex items-baseline justify-between text-sm">
        <p><b>{codigoPedido(ped)}</b> · {formatarData(ped.data_pedido)} · Fornecedor: {fornecedor} · <Distintivo tom={TOM_PED[ped.status]}>{ROTULO_STATUS_PEDIDO[ped.status]}</Distintivo></p>
        <span className="text-xs text-ink-muted">{ped.previsao_entrega ? `Previsão ${formatarData(ped.previsao_entrega)}` : 'Sem previsão'}{ped.condicao_pagamento ? ` · ${ped.condicao_pagamento}` : ''}</span>
      </div>
      {ped.observacao && <p className="rounded-md border border-line bg-surface/60 p-2 text-sm whitespace-pre-line">{ped.observacao}</p>}
      <div className="overflow-x-auto"><table className="w-full text-sm">
        <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-3 py-2 font-medium">Item</th><th className="px-3 py-2 font-medium">Destino</th><th className="px-3 py-2 text-right font-medium">Qtd</th><th className="px-3 py-2 text-right font-medium">Valor unit.</th><th className="px-3 py-2 text-right font-medium">Total</th><th className="px-3 py-2 text-right font-medium">Recebido</th></tr></thead>
        <tbody>
          {(itens.data ?? []).map((i) => (
            <tr key={i.id} className="border-b border-line last:border-0">
              <td className="px-3 py-2">{i.descricao}</td>
              <td className="px-3 py-2 text-xs">{ROTULO_DESTINO[i.destino]}</td>
              <td className="px-3 py-2 text-right tabular-nums">{i.quantidade}</td>
              <td className="px-3 py-2 text-right tabular-nums">{formatarMoeda(i.valor_unitario)}</td>
              <td className="px-3 py-2 text-right tabular-nums">{formatarMoeda(i.quantidade * i.valor_unitario)}</td>
              <td className="px-3 py-2 text-right tabular-nums text-ink-muted">{i.quantidade_recebida}</td>
            </tr>
          ))}
        </tbody>
      </table></div>
      <div className="rounded-md border border-line bg-surface/60 p-3 text-sm">
        <p>Itens: <b className="tabular-nums">{formatarMoeda(totais.data?.total_itens ?? 0)}</b> · Frete: <b className="tabular-nums">{formatarMoeda(ped.valor_frete)}</b> · Desconto: <b className="tabular-nums">−{formatarMoeda(ped.valor_desconto)}</b> · <span className="text-base">Total: <b className="tabular-nums">{formatarMoeda(totais.data?.total_final ?? 0)}</b></span></p>
      </div>
      <p className="text-xs text-ink-muted">Recebimento com nota fiscal e geração de lançamento financeiro chega na próxima etapa (55B).</p>
      <div className="flex justify-end gap-2 border-t border-line pt-3">
        {ped.status === 'aberto' && <Botao variante="perigo" onClick={() => cancelar.mutate({ id: ped.id }, { onSuccess: aoFechar })} carregando={cancelar.isPending}>Cancelar pedido</Botao>}
        <Botao variante="secundario" onClick={aoFechar}>Fechar</Botao>
      </div>
    </div>
  )
}

export function ComprasPage() {
  const [aba, setAba] = useState<Aba>('requisicoes')
  const [modalNova, setModalNova] = useState(false)
  const [reqAberta, setReqAberta] = useState<Requisicao | null>(null)
  const [pedAberto, setPedAberto] = useState<Pedido | null>(null)
  const negocios = useNegocios()
  const pessoas = usePessoas()
  const requisicoes = useRequisicoes()
  const pedidos = usePedidos()
  const [negocioId, setNegocioId] = useState('')
  const servnet = (negocios.data ?? []).find((n) => n.nome.toLowerCase().includes('servnet')) ?? (negocios.data ?? [])[0]
  const negocioAtual = negocioId || servnet?.id || ''
  const nomeNegocio = useMemo(() => new Map((negocios.data ?? []).map((n) => [n.id, n.nome])), [negocios.data])
  const nomeFornecedor = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const reqFiltradas = (requisicoes.data ?? []).filter((r) => !negocioAtual || r.negocio_id === negocioAtual)
  const pedFiltrados = (pedidos.data ?? []).filter((p) => !negocioAtual || p.negocio_id === negocioAtual)
  const pendentes = reqFiltradas.filter((r) => r.status === 'pendente').length

  return (
    <>
      <CabecalhoPagina titulo="Compras" descricao="Requisição → Aprovação → Pedido → Recebimento → Nota → Pagamento"
        acoes={<Botao onClick={() => setModalNova(true)} disabled={!negocioAtual}>Nova requisição</Botao>} />

      {pendentes > 0 && aba !== 'requisicoes' && (
        <div className="mb-4"><Alerta tipo="info" titulo={`${pendentes} requisição(ões) pendente(s) de aprovação`}>Você é o único aprovador; abra a aba Requisições para decidir.</Alerta></div>
      )}

      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div role="tablist" className="flex gap-1 rounded-md border border-line p-1 text-sm">
          {(['requisicoes', 'pedidos'] as Aba[]).map((a) => (
            <button key={a} role="tab" aria-selected={aba === a} onClick={() => setAba(a)} className={`rounded px-3 py-1.5 ${aba === a ? 'bg-brand-600 text-white' : 'text-ink-muted hover:text-ink'}`}>
              {a === 'requisicoes' ? `Requisições${pendentes > 0 ? ` (${pendentes})` : ''}` : 'Pedidos'}
            </button>
          ))}
        </div>
        <select aria-label="Negócio" value={negocioAtual} onChange={(e) => setNegocioId(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
          {(negocios.data ?? []).filter((n) => n.ativo).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
        </select>
      </div>

      {(requisicoes.isPending || pedidos.isPending) && <Carregando />}

      {aba === 'requisicoes' && requisicoes.isSuccess && (
        <Cartao className="p-0">
          {reqFiltradas.length === 0 ? <p className="px-6 py-12 text-center text-sm text-ink-muted">Nenhuma requisição. Clique em "Nova requisição".</p> : (
            <div className="overflow-x-auto"><table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Número</th><th className="px-4 py-2 font-medium">Data</th><th className="px-4 py-2 font-medium">Negócio</th><th className="px-4 py-2 font-medium">Justificativa</th><th className="px-4 py-2 font-medium">Status</th><th className="px-4 py-2"></th></tr></thead>
              <tbody>
                {reqFiltradas.map((r) => (
                  <tr key={r.id} className="border-b border-line last:border-0 hover:bg-surface">
                    <td className="px-4 py-2 font-mono text-xs">{codigoRequisicao(r)}</td>
                    <td className="whitespace-nowrap px-4 py-2 tabular-nums">{formatarData(r.criado_em)}</td>
                    <td className="px-4 py-2">{nomeNegocio.get(r.negocio_id) ?? '—'}</td>
                    <td className="max-w-96 truncate px-4 py-2 text-ink-muted" title={r.justificativa ?? ''}>{r.justificativa ?? '—'}</td>
                    <td className="px-4 py-2"><Distintivo tom={TOM_REQ[r.status]}>{ROTULO_STATUS_REQ[r.status]}</Distintivo></td>
                    <td className="whitespace-nowrap px-4 py-2 text-right"><button type="button" className="text-brand-700 hover:underline" onClick={() => setReqAberta(r)}>Abrir</button></td>
                  </tr>
                ))}
              </tbody>
            </table></div>
          )}
        </Cartao>
      )}

      {aba === 'pedidos' && pedidos.isSuccess && (
        <Cartao className="p-0">
          {pedFiltrados.length === 0 ? <p className="px-6 py-12 text-center text-sm text-ink-muted">Nenhum pedido. Aprove uma requisição para gerar o pedido.</p> : (
            <div className="overflow-x-auto"><table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Número</th><th className="px-4 py-2 font-medium">Data</th><th className="px-4 py-2 font-medium">Fornecedor</th><th className="px-4 py-2 font-medium">Previsão</th><th className="px-4 py-2 font-medium">Condição</th><th className="px-4 py-2 font-medium">Status</th><th className="px-4 py-2"></th></tr></thead>
              <tbody>
                {pedFiltrados.map((p) => (
                  <tr key={p.id} className="border-b border-line last:border-0 hover:bg-surface">
                    <td className="px-4 py-2 font-mono text-xs">{codigoPedido(p)}</td>
                    <td className="whitespace-nowrap px-4 py-2 tabular-nums">{formatarData(p.data_pedido)}</td>
                    <td className="px-4 py-2">{p.fornecedor_id ? (nomeFornecedor.get(p.fornecedor_id) ?? '—') : '—'}</td>
                    <td className="whitespace-nowrap px-4 py-2 tabular-nums">{p.previsao_entrega ? formatarData(p.previsao_entrega) : '—'}</td>
                    <td className="px-4 py-2 text-ink-muted">{p.condicao_pagamento ?? '—'}</td>
                    <td className="px-4 py-2"><Distintivo tom={TOM_PED[p.status]}>{ROTULO_STATUS_PEDIDO[p.status]}</Distintivo></td>
                    <td className="whitespace-nowrap px-4 py-2 text-right"><button type="button" className="text-brand-700 hover:underline" onClick={() => setPedAberto(p)}>Abrir</button></td>
                  </tr>
                ))}
              </tbody>
            </table></div>
          )}
        </Cartao>
      )}

      <Modal aberto={modalNova} aoFechar={() => setModalNova(false)} largura="xl" titulo="Nova requisição de compra">
        {modalNova && negocioAtual && <FormularioRequisicao negocioId={negocioAtual} aoFechar={() => setModalNova(false)} />}
      </Modal>
      <Modal aberto={reqAberta !== null} aoFechar={() => setReqAberta(null)} largura="xl" titulo={reqAberta ? codigoRequisicao(reqAberta) : ''}>
        {reqAberta && <DetalheRequisicao req={reqAberta} aoFechar={() => setReqAberta(null)} />}
      </Modal>
      <Modal aberto={pedAberto !== null} aoFechar={() => setPedAberto(null)} largura="xl" titulo={pedAberto ? codigoPedido(pedAberto) : ''}>
        {pedAberto && <DetalhePedido ped={pedAberto} aoFechar={() => setPedAberto(null)} />}
      </Modal>
    </>
  )
}
