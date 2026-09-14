import { useState } from 'react'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { useEstoqueCategorias, useEstoqueItens, useSalvarEstoqueCategoria, useSalvarEstoqueItem } from '../../estoque/api'

/** Código do item gerado do nome (regra do banco: 2–20 chars A-Z 0-9 . _ -), com sufixo para não colidir. */
function codigoDe(nome: string) {
  const base = nome.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase().replace(/[^A-Z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 14) || 'ITEM'
  return `${base}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`
}

export interface EntradaEstoque { item_id: string; quantidade: number }

/** Lançamento de despesa → item físico entra no estoque (compra ligada ao lançamento). Só para lançamento novo. */
export function EntradaEstoqueCampo({ negocioId, valor, atual, aoMudar }: { negocioId: string; valor: string; atual: EntradaEstoque | null; aoMudar: (e: EntradaEstoque | null) => void }) {
  const itens = useEstoqueItens()
  const categorias = useEstoqueCategorias()
  const salvarItem = useSalvarEstoqueItem()
  const salvarCategoria = useSalvarEstoqueCategoria()
  const [criando, setCriando] = useState(false)
  const [nome, setNome] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const lista = (itens.data ?? []).filter((i) => i.negocio_id === negocioId && i.ativo)
  const qtd = atual?.quantidade ?? 1
  const v = Number(valor.replace(',', '.'))
  const unit = atual && qtd > 0 && !Number.isNaN(v) && v > 0 ? v / qtd : null

  async function criarItem() {
    if (nome.trim().length < 2 || salvarItem.isPending) return
    setErro(null)
    try {
      let cat = (categorias.data ?? []).find((c) => c.negocio_id === negocioId && c.ativo)
      if (!cat) cat = await salvarCategoria.mutateAsync({ negocio_id: negocioId, nome: 'Equipamentos' })
      const item = await salvarItem.mutateAsync({ negocio_id: negocioId, categoria_id: cat.id, codigo: codigoDe(nome), nome: nome.trim(), descricao: null, unidade_medida: 'unidade', marca: null, modelo: null, valor_venda: null, quantidade_minima: 0, quantidade_maxima: null, localizacao: null, ativo: true })
      aoMudar({ item_id: item.id, quantidade: qtd })
      setNome(''); setCriando(false)
    } catch (e) { setErro(mensagemDeErro(e)) }
  }

  return (
    <div className="space-y-2 rounded-md border border-line p-3">
      <label className="flex items-center gap-2 text-sm font-medium">
        <input type="checkbox" checked={atual !== null} onChange={(e) => aoMudar(e.target.checked ? { item_id: lista[0]?.id ?? '', quantidade: 1 } : null)} className="size-4 accent-brand-600" />
        Entrada no estoque (item físico: roteador, ONU, cabo…)
      </label>
      {atual === null ? (
        <p className="text-xs text-ink-muted">Marque quando a compra for de algo que fica na prateleira ou vai para a casa do cliente. O item entra no estoque com este valor (custo médio) e fica ligado a este lançamento.</p>
      ) : (
        <>
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="sm:col-span-2">
              <Selecao rotulo="Item" opcoes={[{ valor: '', rotulo: lista.length ? 'Selecione…' : 'Nenhum item neste negócio — crie abaixo' }, ...lista.map((i) => ({ valor: i.id, rotulo: `${i.nome} (${i.quantidade_atual} em estoque)` }))]} value={atual.item_id} onChange={(e) => aoMudar({ ...atual, item_id: e.target.value })} />
            </div>
            <Campo rotulo="Quantidade" type="number" inputMode="decimal" min="0.01" step="0.01" value={String(atual.quantidade)} onChange={(e) => aoMudar({ ...atual, quantidade: Number(e.target.value) })} />
          </div>
          {unit !== null && <p className="text-xs text-ink-muted">Custo unitário: R$ {unit.toFixed(2).replace('.', ',')} (valor do lançamento ÷ quantidade).</p>}
          {!criando ? (
            <button type="button" className="block text-xs font-medium text-brand-600 hover:underline" onClick={() => setCriando(true)}>+ Criar item no estoque</button>
          ) : (
            <div className="space-y-1 rounded-md border border-line bg-surface/60 p-2">
              <div className="flex items-center gap-2">
                <input value={nome} onChange={(e) => setNome(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); void criarItem() } }} placeholder="Nome do item (ex.: Roteador Wi-Fi AC1200)" autoFocus className="h-8 flex-1 rounded-md border border-line bg-white px-2 text-sm outline-none focus:border-brand-600" />
                <Botao type="button" onClick={() => void criarItem()} carregando={salvarItem.isPending || salvarCategoria.isPending} disabled={nome.trim().length < 2}>Criar</Botao>
                <Botao type="button" variante="secundario" onClick={() => { setCriando(false); setErro(null) }}>×</Botao>
              </div>
              <p className="text-xs text-ink-muted">Cria na primeira categoria de estoque do negócio (ou "Equipamentos"); ajuste código, marca e mínimo depois em Estoque.</p>
              {erro && <p className="text-xs text-red-600">{erro}</p>}
            </div>
          )}
        </>
      )}
    </div>
  )
}
