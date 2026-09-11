import { useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Cartao } from '../../../core/ui/Cartao'
import { Carregando } from '../../../core/ui/Carregando'
import { Distintivo } from '../../../core/ui/Distintivo'
import { Modal } from '../../../core/ui/Modal'
import { Selecao } from '../../../core/ui/Selecao'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda, hojeISO } from '../../../core/formatos'
import { usePatrimonioHistorico, usePatrimonios, useSalvarPatrimonio } from '../api'
import { codigoPatrimonio, ROTULO_ESTADO_PAT, ROTULO_STATUS_PAT, type EstadoPatrimonio, type Patrimonio, type StatusPatrimonio } from '../tipos'

const TOM_PAT = { ativo: 'ok', vendido: 'info', perdido: 'alerta', descartado: 'neutro' } as const

function FormPatrimonio({ negocioId, bem, aoFechar }: { negocioId: string; bem: Patrimonio | null; aoFechar: () => void }) {
  const salvar = useSalvarPatrimonio()
  const historico = usePatrimonioHistorico(bem?.id ?? null)
  const [nome, setNome] = useState(bem?.nome ?? '')
  const [serie, setSerie] = useState(bem?.numero_serie ?? '')
  const [valor, setValor] = useState(bem ? String(bem.valor_aquisicao) : '')
  const [dataAq, setDataAq] = useState(bem?.data_aquisicao ?? hojeISO())
  const [nf, setNf] = useState(bem?.nota_fiscal ?? '')
  const [local, setLocal] = useState(bem?.localizacao ?? '')
  const [estado, setEstado] = useState<EstadoPatrimonio>(bem?.estado ?? 'novo')
  const [status, setStatus] = useState<StatusPatrimonio>(bem?.status ?? 'ativo')
  const [obs, setObs] = useState(bem?.observacao ?? '')
  const [erro, setErro] = useState<string | null>(null)
  const baixado = bem != null && bem.status !== 'ativo'

  function enviar() {
    if (nome.trim().length < 2) { setErro('Informe o nome do bem.'); return }
    if (local.trim().length < 2) { setErro('Informe a localização (POP, veículo, escritório…).'); return }
    if (status !== 'ativo' && !window.confirm(`Confirmar a baixa como "${ROTULO_STATUS_PAT[status]}"? Depois disso o bem não pode mais ser alterado.`)) return
    setErro(null)
    salvar.mutate({
      id: bem?.id, negocio_id: negocioId, nome: nome.trim(), numero_serie: serie.trim() || null,
      valor_aquisicao: Math.round(Number(valor.replace(',', '.') || '0') * 100) / 100,
      data_aquisicao: dataAq, nota_fiscal: nf.trim() || null, localizacao: local.trim(),
      estado, status, observacao: obs.trim() || null,
    }, { onSuccess: aoFechar, onError: (e) => setErro(mensagemDeErro(e)) })
  }

  return (
    <div className="space-y-4">
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      {baixado && <Alerta tipo="info">Bem baixado ({ROTULO_STATUS_PAT[bem.status]}) — somente leitura.</Alerta>}
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Nome do bem" value={nome} onChange={(e) => setNome(e.target.value)} maxLength={120} autoFocus placeholder="Ex.: Fusionadora X1" disabled={baixado} />
        <Campo rotulo="Nº de série (opcional)" value={serie} onChange={(e) => setSerie(e.target.value)} maxLength={60} disabled={baixado} />
      </div>
      <div className="grid grid-cols-3 gap-4">
        <Campo rotulo="Valor de aquisição" type="number" step="0.01" min="0" value={valor} onChange={(e) => setValor(e.target.value)} disabled={baixado} />
        <Campo rotulo="Data de aquisição" type="date" value={dataAq} onChange={(e) => setDataAq(e.target.value)} disabled={baixado} />
        <Campo rotulo="Nota fiscal (opcional)" value={nf} onChange={(e) => setNf(e.target.value)} maxLength={60} disabled={baixado} />
      </div>
      <div className="grid grid-cols-3 gap-4">
        <Campo rotulo="Localização" value={local} onChange={(e) => setLocal(e.target.value)} maxLength={100} placeholder="POP Central, veículo, escritório…" disabled={baixado} />
        <Selecao rotulo="Estado" opcoes={(Object.keys(ROTULO_ESTADO_PAT) as EstadoPatrimonio[]).map((v) => ({ valor: v, rotulo: ROTULO_ESTADO_PAT[v] }))} value={estado} onChange={(e) => setEstado(e.target.value as EstadoPatrimonio)} disabled={baixado} />
        {bem != null && !baixado && (
          <Selecao rotulo="Situação" ajuda="Vendido/Perdido/Descartado = baixa definitiva."
            opcoes={(Object.keys(ROTULO_STATUS_PAT) as StatusPatrimonio[]).map((v) => ({ valor: v, rotulo: ROTULO_STATUS_PAT[v] }))}
            value={status} onChange={(e) => setStatus(e.target.value as StatusPatrimonio)} />
        )}
      </div>
      <AreaTexto rotulo="Observação (opcional)" rows={2} maxLength={300} value={obs} onChange={(e) => setObs(e.target.value)} disabled={baixado} />
      {bem != null && (
        <div>
          <p className="mb-1 text-sm font-medium">Histórico</p>
          {historico.isPending ? <Carregando /> : (
            <ul className="max-h-40 divide-y divide-line overflow-y-auto rounded-md border border-line text-sm">
              {(historico.data ?? []).map((h) => <li key={h.id} className="px-3 py-1.5"><span className="text-xs text-ink-muted">{formatarData(h.criado_em.slice(0, 10))}</span> · {h.detalhe}</li>)}
            </ul>
          )}
        </div>
      )}
      <div className="flex justify-end gap-2">
        <Botao variante="secundario" onClick={aoFechar} disabled={salvar.isPending}>Voltar</Botao>
        {!baixado && <Botao onClick={enviar} carregando={salvar.isPending}>{bem ? 'Salvar alterações' : 'Cadastrar bem'}</Botao>}
      </div>
    </div>
  )
}

/** Inventário patrimonial: bens individuais, transferência de local e baixa, com valor total. */
export function AbaPatrimonio({ negocioId }: { negocioId: string }) {
  const patrimonios = usePatrimonios()
  const [modal, setModal] = useState<{ bem: Patrimonio | null } | null>(null)
  const lista = (patrimonios.data ?? []).filter((p) => p.negocio_id === negocioId)
  const ativos = lista.filter((p) => p.status === 'ativo')
  const total = ativos.reduce((s, p) => s + p.valor_aquisicao, 0)

  function exportarCsv() {
    const cab = ['numero', 'nome', 'serie', 'valor_aquisicao', 'data_aquisicao', 'nota_fiscal', 'localizacao', 'estado', 'situacao']
    const corpo = lista.map((p) => [codigoPatrimonio(p), p.nome, p.numero_serie ?? '', String(p.valor_aquisicao).replace('.', ','), p.data_aquisicao, p.nota_fiscal ?? '', p.localizacao, ROTULO_ESTADO_PAT[p.estado], ROTULO_STATUS_PAT[p.status]].join(';'))
    const url = URL.createObjectURL(new Blob(['﻿' + [cab.join(';'), ...corpo].join('\n')], { type: 'text/csv;charset=utf-8' }))
    const a = document.createElement('a')
    a.href = url
    a.download = `inventario-patrimonial-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <Cartao className="p-0">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-6 py-3">
        <div>
          <h2 className="text-sm font-semibold">Inventário patrimonial</h2>
          <p className="text-xs text-ink-muted">{ativos.length} bem(ns) ativo(s) · valor total {formatarMoeda(total)}</p>
        </div>
        <span className="flex gap-2">
          <Botao variante="secundario" onClick={exportarCsv} disabled={lista.length === 0}>Exportar CSV</Botao>
          <Botao onClick={() => setModal({ bem: null })}>Novo bem</Botao>
        </span>
      </div>
      {patrimonios.isPending ? <div className="p-6"><Carregando /></div> : lista.length === 0 ? (
        <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhum bem cadastrado. Patrimônio é o que não se consome: fusionadora, power meter, estante, nobreak, escada…</p>
      ) : (
        <div className="overflow-x-auto"><table className="w-full text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line">
            <th className="px-6 py-3">Nº</th><th className="px-6 py-3">Bem</th><th className="px-6 py-3">Localização</th><th className="px-6 py-3">Estado</th><th className="px-6 py-3 text-right">Valor</th><th className="px-6 py-3">Situação</th>
          </tr></thead>
          <tbody>{lista.map((p) => (
            <tr key={p.id} onClick={() => setModal({ bem: p })} className="cursor-pointer border-b border-line last:border-0 hover:bg-surface">
              <td className="px-6 py-3 font-mono text-xs">{codigoPatrimonio(p)}</td>
              <td className="px-6 py-3"><span className="font-medium">{p.nome}</span>{p.numero_serie && <span className="ml-2 text-xs text-ink-muted">SN {p.numero_serie}</span>}</td>
              <td className="px-6 py-3">{p.localizacao}</td>
              <td className="px-6 py-3">{ROTULO_ESTADO_PAT[p.estado]}</td>
              <td className="px-6 py-3 text-right tabular-nums">{formatarMoeda(p.valor_aquisicao)}</td>
              <td className="px-6 py-3"><Distintivo tom={TOM_PAT[p.status]}>{ROTULO_STATUS_PAT[p.status]}</Distintivo></td>
            </tr>
          ))}</tbody>
        </table></div>
      )}
      <p className="border-t border-line px-6 py-2 text-xs text-ink-muted">Patrimônio não entra em alerta de reposição. Para registrar a despesa da compra, lance no Financeiro em categoria de natureza "Investimento / ativo".</p>
      <Modal aberto={modal !== null} aoFechar={() => setModal(null)} largura="lg" titulo={modal?.bem ? `${codigoPatrimonio(modal.bem)} · ${modal.bem.nome}` : 'Novo bem patrimonial'}>
        {modal && <FormPatrimonio key={modal.bem?.id ?? 'novo'} negocioId={negocioId} bem={modal.bem} aoFechar={() => setModal(null)} />}
      </Modal>
    </Cartao>
  )
}
