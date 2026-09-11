import { useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarMoeda, hojeISO } from '../../../core/formatos'
import { usePessoas } from '../../pessoas/api'
import { useContratos } from '../../contratos/api'
import { codigoContrato } from '../../contratos/tipos'
import { useCtos, usePortasCto } from '../../ftth/api'
import { useRegistrarInstalacao } from '../api'
import { fmtQtd, type EstoqueItem } from '../tipos'

interface LinhaItem { itemId: string; quantidade: string }

/** Registro de instalação: materiais do estoque + mão de obra, vinculados ao cliente/contrato e à porta da CTO. */
export function NovaInstalacao({ negocioId, itens, aoFechar }: { negocioId: string; itens: EstoqueItem[]; aoFechar: () => void }) {
  const pessoas = usePessoas()
  const contratos = useContratos()
  const ctos = useCtos()
  const registrar = useRegistrarInstalacao()
  const [data, setData] = useState(hojeISO())
  const [pessoaId, setPessoaId] = useState('')
  const [contratoId, setContratoId] = useState('')
  const [ctoId, setCtoId] = useState('')
  const [portaId, setPortaId] = useState('')
  const [linhas, setLinhas] = useState<LinhaItem[]>([{ itemId: '', quantidade: '' }])
  const [maoDeObra, setMaoDeObra] = useState('')
  const [tecnico, setTecnico] = useState('')
  const [obs, setObs] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const portas = usePortasCto(ctoId || null)

  const contratosDoCliente = (contratos.data ?? []).filter((c) => c.pessoa_id === pessoaId && c.negocio_id === negocioId && c.status === 'ativo')
  const ctosDoNegocio = (ctos.data ?? []).filter((c) => c.negocio_id === negocioId && c.tipo === 'cto' && c.status === 'ativa')
  const portasDisponiveis = (portas.data ?? []).filter((p) => !p.defeito && (p.status === 'livre' || (p.status === 'reservada' && p.pessoa_id === pessoaId) || (p.status === 'ocupada' && p.pessoa_id === pessoaId)))
  const itemDe = (id: string) => itens.find((i) => i.id === id)
  const custoMaterial = linhas.reduce((s, l) => {
    const it = itemDe(l.itemId); const q = Number(l.quantidade.replace(',', '.')) || 0
    return s + (it ? q * it.valor_custo : 0)
  }, 0)
  const custoTotal = custoMaterial + (Number(maoDeObra.replace(',', '.')) || 0)

  function salvar() {
    setErro(null)
    if (!pessoaId) { setErro('Escolha o cliente.'); return }
    const itensOk = linhas.filter((l) => l.itemId && Number(l.quantidade.replace(',', '.')) > 0)
    if (portaId && !contratoId) { setErro('Para vincular a porta da CTO escolha o contrato ativo do cliente.'); return }
    if (itensOk.length === 0 && !(Number(maoDeObra.replace(',', '.')) > 0)) { setErro('Informe ao menos um material ou a mão de obra.'); return }
    registrar.mutate({
      negocio_id: negocioId, pessoa_id: pessoaId, contrato_id: contratoId || null, porta_id: portaId || null, data,
      itens: itensOk.map((l) => ({ item_id: l.itemId, quantidade: Number(l.quantidade.replace(',', '.')) })),
      mao_de_obra: Math.round((Number(maoDeObra.replace(',', '.')) || 0) * 100) / 100,
      tecnico: tecnico.trim() || null, observacao: obs.trim() || null,
    }, { onSuccess: aoFechar })
  }

  return (
    <div className="space-y-4">
      {(erro ?? (registrar.error ? mensagemDeErro(registrar.error) : null)) && <Alerta tipo="erro">{erro ?? mensagemDeErro(registrar.error)}</Alerta>}
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Data" type="date" value={data} onChange={(e) => setData(e.target.value)} />
        <Selecao rotulo="Cliente" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(pessoas.data ?? []).filter((p) => p.ativo).map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={pessoaId} onChange={(e) => { setPessoaId(e.target.value); setContratoId(''); setPortaId('') }} />
      </div>
      <div className="grid grid-cols-3 gap-4">
        <Selecao rotulo="Contrato (opcional)" opcoes={[{ valor: '', rotulo: pessoaId ? (contratosDoCliente.length ? 'Nenhum' : 'Sem contrato ativo') : 'Escolha o cliente' }, ...contratosDoCliente.map((c) => ({ valor: c.id, rotulo: `${codigoContrato(c)} · ${formatarMoeda(c.valor)}` }))]} value={contratoId} onChange={(e) => setContratoId(e.target.value)} disabled={!pessoaId} />
        <Selecao rotulo="CTO (opcional)" opcoes={[{ valor: '', rotulo: 'Nenhuma' }, ...ctosDoNegocio.map((c) => ({ valor: c.id, rotulo: c.codigo }))]} value={ctoId} onChange={(e) => { setCtoId(e.target.value); setPortaId('') }} />
        <Selecao rotulo="Porta" opcoes={[{ valor: '', rotulo: ctoId ? (portasDisponiveis.length ? 'Selecione…' : 'Nenhuma disponível') : 'Escolha a CTO' }, ...portasDisponiveis.map((p) => ({ valor: p.id, rotulo: `Porta ${p.numero}${p.status !== 'livre' ? ` (${p.status === 'ocupada' ? 'do cliente' : 'reservada'})` : ''}` }))]} value={portaId} onChange={(e) => setPortaId(e.target.value)} disabled={!ctoId} />
      </div>
      {portaId && !contratoId && <p className="text-xs text-red-700">A porta será vinculada ao contrato: escolha o contrato ativo do cliente.</p>}
      <div>
        <p className="mb-1 text-sm font-medium">Materiais usados (baixa pelo custo médio)</p>
        {linhas.map((l, i) => {
          const it = itemDe(l.itemId)
          return (
            <div key={i} className="mb-2 flex items-end gap-2">
              <div className="flex-1"><Selecao rotulo={i === 0 ? 'Item' : ''} opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...itens.filter((x) => x.ativo).map((x) => ({ valor: x.id, rotulo: `${x.codigo} · ${x.nome} (${fmtQtd(x.quantidade_atual)} ${x.unidade_medida})` }))]} value={l.itemId} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, itemId: e.target.value } : x)))} /></div>
              <input type="number" step="0.01" min="0.01" placeholder="Qtd." aria-label="Quantidade" value={l.quantidade} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, quantidade: e.target.value } : x)))} className="h-10 w-24 rounded-md border border-line bg-white px-2 text-sm" />
              <span className="w-24 pb-2.5 text-right text-xs tabular-nums text-ink-muted">{it ? formatarMoeda((Number(l.quantidade.replace(',', '.')) || 0) * it.valor_custo) : ''}</span>
              <button type="button" aria-label="Remover material" className="pb-2 text-ink-muted hover:text-red-700" onClick={() => setLinhas((xs) => xs.filter((_, j) => j !== i))}>×</button>
            </div>
          )
        })}
        <Botao variante="secundario" onClick={() => setLinhas((xs) => [...xs, { itemId: '', quantidade: '' }])}>+ Material</Botao>
      </div>
      <div className="grid grid-cols-3 gap-4">
        <Campo rotulo="Mão de obra (R$)" type="number" step="0.01" min="0" value={maoDeObra} onChange={(e) => setMaoDeObra(e.target.value)} />
        <Campo rotulo="Técnico (opcional)" value={tecnico} onChange={(e) => setTecnico(e.target.value)} maxLength={80} />
        <Campo rotulo="Observação (opcional)" value={obs} onChange={(e) => setObs(e.target.value)} maxLength={300} />
      </div>
      <p className="text-xs text-ink-muted">Material: {formatarMoeda(custoMaterial)} · Custo total da instalação: <b>{formatarMoeda(custoTotal)}</b>. A mão de obra entra no payback; se for paga a terceiro, lance a despesa no Financeiro.</p>
      <div className="flex justify-end gap-2">
        <Botao variante="secundario" onClick={aoFechar} disabled={registrar.isPending}>Cancelar</Botao>
        <Botao onClick={salvar} carregando={registrar.isPending}>Registrar instalação</Botao>
      </div>
    </div>
  )
}
