import { useMemo, useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Modal } from '../../../core/ui/Modal'
import { Cartao } from '../../../core/ui/Cartao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../../core/formatos'
import { usePessoas } from '../../pessoas/api'
import { useContas } from '../../contas/api'
import { useCategorias } from '../../categorias/api'
import { useAbrirDevolucaoFornecedor, useDevolucoesFornecedor, useEstoqueItens, useResolverDevolucaoFornecedor } from '../api'
import { ROTULO_DEVOLUCAO, type DevolucaoFornecedor } from '../tipos'

const TOM = { aberta: 'alerta', reembolsada: 'ok', trocada: 'info', negada: 'neutro' } as const

/** Devolução ao fornecedor (RMA): item com defeito sai do estoque e vira pendência
 *  no Contas a Receber (reembolso previsto) até o fornecedor resolver. */
export function AbaDevolucaoFornecedor({ negocioId }: { negocioId: string }) {
  const devolucoes = useDevolucoesFornecedor()
  const itens = useEstoqueItens()
  const pessoas = usePessoas()
  const contas = useContas()
  const categorias = useCategorias()
  const abrir = useAbrirDevolucaoFornecedor()
  const resolver = useResolverDevolucaoFornecedor()

  const [filtro, setFiltro] = useState('aberta')
  const [modal, setModal] = useState<'abrir' | null>(null)
  const [resolucao, setResolucao] = useState<{ d: DevolucaoFornecedor; desfecho: 'reembolso' | 'troca' | 'negada' } | null>(null)
  const [itemId, setItemId] = useState(''); const [quantidade, setQuantidade] = useState('1'); const [motivo, setMotivo] = useState('')
  const [contaId, setContaId] = useState(''); const [categoriaId, setCategoriaId] = useState(''); const [pessoaId, setPessoaId] = useState('')
  const [obsResolucao, setObsResolucao] = useState('')

  const nomeItem = useMemo(() => new Map((itens.data ?? []).map((i) => [i.id, `${i.codigo} · ${i.nome}`])), [itens.data])
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const catsReceita = (categorias.data ?? []).filter((c) => c.tipo === 'receita')
  const lista = (devolucoes.data ?? []).filter((d) => d.negocio_id === negocioId).filter((d) => !filtro || d.status === filtro)
  const erro = abrir.error ?? resolver.error
  const ocupado = abrir.isPending || resolver.isPending

  function abrirDevolucao() {
    abrir.mutate(
      { p_item_id: itemId, p_quantidade: Number(quantidade.replace(',', '.')), p_motivo: motivo.trim(), p_conta_id: contaId, p_categoria_id: categoriaId, p_pessoa_id: pessoaId || null },
      { onSuccess: () => { setModal(null); setItemId(''); setQuantidade('1'); setMotivo(''); setContaId(''); setCategoriaId(''); setPessoaId(''); abrir.reset() } },
    )
  }
  function confirmarResolucao() {
    if (!resolucao) return
    resolver.mutate(
      { p_id: resolucao.d.id, p_desfecho: resolucao.desfecho, p_observacao: obsResolucao.trim() || null },
      { onSuccess: () => { setResolucao(null); setObsResolucao(''); resolver.reset() } },
    )
  }

  return (
    <Cartao className="p-0">
      <div className="flex flex-wrap items-center gap-2 border-b border-line px-4 py-3 text-sm">
        <select aria-label="Status" value={filtro} onChange={(e) => setFiltro(e.target.value)} className="h-9 rounded-md border border-line bg-white px-2">
          <option value="">Todas</option><option value="aberta">Abertas</option><option value="reembolsada">Reembolsadas</option><option value="trocada">Trocadas</option><option value="negada">Negadas</option>
        </select>
        <span className="text-ink-muted">{lista.length} devolução(ões)</span>
        <span className="flex-1" />
        <Botao variante="secundario" onClick={() => setModal('abrir')}>Abrir devolução</Botao>
      </div>
      {erro != null && <div className="px-4 pt-3"><Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta></div>}
      {lista.length === 0 ? <p className="px-6 py-12 text-center text-sm text-ink-muted">Nenhuma devolução ao fornecedor. Item com defeito na compra? Abra uma devolução — o reembolso entra no Contas a Receber como pendência.</p> : (
        <div className="overflow-x-auto"><table className="w-full text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Item</th><th className="px-4 py-2 font-medium">Qtd.</th><th className="px-4 py-2 font-medium">Valor</th><th className="px-4 py-2 font-medium">Fornecedor</th><th className="px-4 py-2 font-medium">Enviada em</th><th className="px-4 py-2 font-medium">Status</th><th className="px-4 py-2"></th></tr></thead>
          <tbody>
            {lista.map((d) => (
              <tr key={d.id} className="border-b border-line last:border-0 hover:bg-surface">
                <td className="px-4 py-2">{nomeItem.get(d.item_id) ?? '—'}</td>
                <td className="px-4 py-2 tabular-nums">{d.quantidade}</td>
                <td className="whitespace-nowrap px-4 py-2 tabular-nums">{formatarMoeda(d.valor)}</td>
                <td className="px-4 py-2">{d.pessoa_id ? (nomePessoa.get(d.pessoa_id) ?? '—') : '—'}</td>
                <td className="whitespace-nowrap px-4 py-2 tabular-nums">{formatarData(d.data_envio)}{d.data_resolucao ? ` → ${formatarData(d.data_resolucao)}` : ''}</td>
                <td className="px-4 py-2"><Distintivo tom={TOM[d.status]}>{ROTULO_DEVOLUCAO[d.status]}</Distintivo></td>
                <td className="whitespace-nowrap px-4 py-2 text-right text-xs">
                  {d.status === 'aberta' && (
                    <>
                      <button type="button" className="text-brand-700 hover:underline" onClick={() => { setResolucao({ d, desfecho: 'reembolso' }); setObsResolucao('') }}>Reembolso</button>
                      <button type="button" className="ml-3 text-brand-700 hover:underline" onClick={() => { setResolucao({ d, desfecho: 'troca' }); setObsResolucao('') }}>Troca</button>
                      <button type="button" className="ml-3 text-red-700 hover:underline" onClick={() => { setResolucao({ d, desfecho: 'negada' }); setObsResolucao('') }}>Negada</button>
                    </>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table></div>
      )}

      <Modal aberto={modal === 'abrir'} aoFechar={() => { setModal(null); abrir.reset() }} largura="md" titulo="Abrir devolução ao fornecedor">
        {modal === 'abrir' && (
          <div className="space-y-4">
            {abrir.error != null && <Alerta tipo="erro">{mensagemDeErro(abrir.error)}</Alerta>}
            <p className="text-xs text-ink-muted">A unidade sai do estoque pelo custo médio; o reembolso nasce como pendência no Contas a Receber até o fornecedor resolver.</p>
            <Selecao rotulo="Item" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(itens.data ?? []).filter((i) => i.negocio_id === negocioId && i.ativo).map((i) => ({ valor: i.id, rotulo: `${i.codigo} · ${i.nome}` }))]} value={itemId} onChange={(e) => setItemId(e.target.value)} />
            <Campo rotulo="Quantidade" value={quantidade} onChange={(e) => setQuantidade(e.target.value)} />
            <Campo rotulo="Motivo (obrigatório)" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={300} />
            <Selecao rotulo="Conta do reembolso" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(contas.data ?? []).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} />
            <Selecao rotulo="Categoria da receita" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...catsReceita.map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={categoriaId} onChange={(e) => setCategoriaId(e.target.value)} />
            <Selecao rotulo="Fornecedor (opcional)" opcoes={[{ valor: '', rotulo: 'Nenhum' }, ...(pessoas.data ?? []).filter((p) => p.ativo).map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={pessoaId} onChange={(e) => setPessoaId(e.target.value)} />
            <div className="flex justify-end"><Botao disabled={!itemId || !Number(quantidade.replace(',', '.')) || motivo.trim().length < 3 || !contaId || !categoriaId} carregando={abrir.isPending} onClick={abrirDevolucao}>Abrir devolução</Botao></div>
          </div>
        )}
      </Modal>

      <Modal aberto={resolucao !== null} aoFechar={() => setResolucao(null)} largura="md" titulo={resolucao ? `Resolver: ${resolucao.desfecho === 'reembolso' ? 'reembolso recebido' : resolucao.desfecho === 'troca' ? 'troca' : 'negada'}` : ''}>
        {resolucao && (
          <div className="space-y-4">
            {resolver.error != null && <Alerta tipo="erro">{mensagemDeErro(resolver.error)}</Alerta>}
            <p className="text-sm">{nomeItem.get(resolucao.d.item_id)} — {formatarMoeda(resolucao.d.valor)}</p>
            <p className="text-xs text-ink-muted">
              {resolucao.desfecho === 'reembolso' && 'Dá baixa na receita prevista, hoje. Entra na Conciliação.'}
              {resolucao.desfecho === 'troca' && 'Unidade nova entra no estoque pelo mesmo valor (custo médio preservado); a receita prevista é cancelada.'}
              {resolucao.desfecho === 'negada' && 'A receita prevista é cancelada. A saída já registrada fica como perda.'}
            </p>
            <Campo rotulo="Observação (opcional)" value={obsResolucao} onChange={(e) => setObsResolucao(e.target.value)} maxLength={300} />
            <div className="flex justify-end gap-2">
              <Botao variante="secundario" onClick={() => setResolucao(null)} disabled={ocupado}>Cancelar</Botao>
              <Botao variante={resolucao.desfecho === 'negada' ? 'perigo' : 'primario'} carregando={ocupado} onClick={confirmarResolucao}>Confirmar</Botao>
            </div>
          </div>
        )}
      </Modal>
    </Cartao>
  )
}
