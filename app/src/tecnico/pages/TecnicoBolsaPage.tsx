import { useState } from 'react'
import { useOutletContext } from 'react-router'
import { Alerta } from '../../core/ui/Alerta'
import { Botao } from '../../core/ui/Botao'
import { Campo } from '../../core/ui/Campo'
import { Selecao } from '../../core/ui/Selecao'
import { Distintivo } from '../../core/ui/Distintivo'
import { Carregando } from '../../core/ui/Carregando'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { fmtQtd } from '../../modules/estoque/tipos'
import type { Tecnico } from '../../modules/os/tipos'
import { useItensDoNegocio, useMinhaBolsa, usePedirReposicao, usePerdaMinha } from '../api'

export function TecnicoBolsaPage() {
  const eu = useOutletContext<Tecnico>()
  const bolsa = useMinhaBolsa()
  const itens = useItensDoNegocio()
  const reposicao = usePedirReposicao()
  const perda = usePerdaMinha()
  const [acao, setAcao] = useState<'reposicao' | 'perda'>('reposicao')
  const [itemId, setItemId] = useState('')
  const [qtd, setQtd] = useState('')
  const [motivo, setMotivo] = useState('')
  const [ok, setOk] = useState<string | null>(null)
  const nomeItem = (id: string) => { const i = (itens.data ?? []).find((x) => x.id === id); return i ? `${i.codigo} · ${i.nome}` : '—' }
  const v = Number(qtd.replace(',', '.'))
  const erro = reposicao.error ?? perda.error

  function enviar() {
    setOk(null)
    if (!itemId || !(v > 0)) return
    if (acao === 'reposicao') reposicao.mutate({ p_item_id: itemId, p_quantidade: v }, { onSuccess: () => { setOk('Pedido enviado ao administrador.'); setQtd('') } })
    else {
      if (motivo.trim().length < 3) return
      perda.mutate({ p_tecnico_id: eu.id, p_item_id: itemId, p_quantidade: v, p_avaria: false, p_motivo: motivo.trim() }, { onSuccess: () => { setOk('Perda registrada.'); setQtd(''); setMotivo('') } })
    }
  }

  if (bolsa.isPending) return <Carregando />

  return (
    <div className="space-y-4">
      {erro != null && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}
      {ok && <Alerta tipo="info">{ok}</Alerta>}
      <div className="space-y-2">
        {(bolsa.data ?? []).length === 0 && <p className="rounded-md border border-line bg-white p-4 text-center text-sm text-ink-muted">Bolsa vazia. Peça reposição ao administrador.</p>}
        {(bolsa.data ?? []).map((b) => (
          <div key={b.id} className="flex items-center justify-between rounded-lg border border-line bg-white p-3 text-sm">
            <span className="font-medium">{nomeItem(b.item_id)}</span>
            <span className="flex items-center gap-2">
              <span className={`tabular-nums ${b.quantidade < 0 ? 'font-semibold text-red-700' : ''}`}>{fmtQtd(b.quantidade)}</span>
              {b.quantidade < b.quantidade_minima && <Distintivo tom="alerta">{b.quantidade < 0 ? 'Negativo' : 'Baixo'}</Distintivo>}
            </span>
          </div>
        ))}
      </div>
      <div className="space-y-2 rounded-lg border border-line bg-white p-3">
        <Selecao rotulo="Ação" opcoes={[{ valor: 'reposicao', rotulo: 'Pedir reposição' }, { valor: 'perda', rotulo: 'Registrar perda/avaria' }]} value={acao} onChange={(e) => setAcao(e.target.value as typeof acao)} />
        <Selecao rotulo="Item" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(itens.data ?? []).map((i) => ({ valor: i.id, rotulo: `${i.codigo} · ${i.nome}` }))]} value={itemId} onChange={(e) => setItemId(e.target.value)} />
        <Campo rotulo="Quantidade" type="number" step="0.01" min="0" value={qtd} onChange={(e) => setQtd(e.target.value)} />
        {acao === 'perda' && <Campo rotulo="Motivo (obrigatório)" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={300} placeholder="Ex.: caiu do poste, conector quebrou" />}
        <Botao onClick={enviar} carregando={reposicao.isPending || perda.isPending} disabled={!itemId || !(v > 0) || (acao === 'perda' && motivo.trim().length < 3)}>
          {acao === 'reposicao' ? 'Enviar pedido' : 'Registrar perda'}
        </Botao>
      </div>
    </div>
  )
}
