import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarMoeda } from '../../../core/formatos'
import { supabase } from '../../../core/supabase/client'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { useNegocios } from '../../negocios/api'
import { usePaybackContratos } from '../../estoque/api'
import { useOrdens, useTecnicos } from '../../os/api'
import { fmtMinutos } from '../../os/tipos'

interface LinhaBi {
  negocio_id: string
  negocio: string
  mes: string
  novos: number
  cancelamentos: number
  ativos_inicio: number
  ativos_fim: number
  churn_pct: number
  mrr: number
  ticket_medio: number
  previsto: number
  recebido: number
  vencido_aberto: number
  inadimplencia_pct: number
}

function Indicador({ rotulo, valor, detalhe, alerta = false }: { rotulo: string; valor: string; detalhe?: string; alerta?: boolean }) {
  return (
    <Cartao className="p-4">
      <p className="text-xs uppercase tracking-wide text-ink-muted">{rotulo}</p>
      <p className={`mt-1 text-xl font-semibold tabular-nums ${alerta ? 'text-red-700' : ''}`}>{valor}</p>
      {detalhe && <p className="text-xs text-ink-muted">{detalhe}</p>}
    </Cartao>
  )
}

/** BI gerencial: churn, ticket, inadimplência, MRR, payback e técnicos — dados calculados em tempo real. */
export function GerencialPage() {
  const { organizacao } = useOrganizacao()
  const negocios = useNegocios()
  const paybacks = usePaybackContratos()
  const ordens = useOrdens()
  const tecnicos = useTecnicos()
  const [negocioId, setNegocioId] = useState('')
  const servnet = (negocios.data ?? []).find((n) => n.nome.toLowerCase().includes('servnet')) ?? (negocios.data ?? [])[0]
  const negocioAtual = negocioId || servnet?.id || ''

  const bi = useQuery({
    queryKey: ['gerencial', organizacao.id],
    queryFn: async (): Promise<LinhaBi[]> => {
      const { data, error } = await supabase.from('vw_bi_mensal_negocio').select('*').eq('organizacao_id', organizacao.id).order('mes')
      if (error) throw error
      return (data ?? []).map((r) => ({
        ...r, novos: Number(r.novos), cancelamentos: Number(r.cancelamentos), ativos_inicio: Number(r.ativos_inicio), ativos_fim: Number(r.ativos_fim),
        churn_pct: Number(r.churn_pct), mrr: Number(r.mrr), ticket_medio: Number(r.ticket_medio), previsto: Number(r.previsto),
        recebido: Number(r.recebido), vencido_aberto: Number(r.vencido_aberto), inadimplencia_pct: Number(r.inadimplencia_pct),
      })) as LinhaBi[]
    },
  })

  const linhas = useMemo(() => (bi.data ?? []).filter((l) => l.negocio_id === negocioAtual), [bi.data, negocioAtual])
  const atual = linhas.at(-1)
  const paybackNegocio = (paybacks.data ?? []).filter((p) => p.negocio_id === negocioAtual && p.payback_estimado_meses != null)
  const paybackMedio = paybackNegocio.length ? paybackNegocio.reduce((s, p) => s + (p.payback_estimado_meses ?? 0), 0) / paybackNegocio.length : null

  const corte90 = useMemo(() => Date.now() - 90 * 86_400_000, [])
  const encerradas90 = (ordens.data ?? []).filter((o) => o.negocio_id === negocioAtual && o.status === 'encerrado' && o.data_fim && new Date(o.data_fim).getTime() > corte90)
  const tecnicosNegocio = (tecnicos.data ?? []).filter((t) => t.negocio_id === negocioAtual)
  const desempenho = tecnicosNegocio.map((t) => {
    const minhas = encerradas90.filter((o) => o.tecnico_id === t.id)
    const comTempo = minhas.filter((o) => o.tempo_total_minutos != null)
    const notas = minhas.filter((o) => o.avaliacao_nota != null)
    return {
      id: t.id, nome: t.nome, chamados: minhas.length,
      tempoMedio: comTempo.length ? Math.round(comTempo.reduce((s, o) => s + (o.tempo_total_minutos ?? 0), 0) / comTempo.length) : null,
      nota: notas.length ? (notas.reduce((s, o) => s + (o.avaliacao_nota ?? 0), 0) / notas.length).toFixed(1) : null,
      retornos: minhas.filter((o) => o.retorno).length,
    }
  })

  function exportarCsv() {
    const cab = ['mes', 'novos', 'cancelamentos', 'ativos_inicio', 'ativos_fim', 'churn_pct', 'mrr', 'ticket_medio', 'previsto', 'recebido', 'vencido_aberto', 'inadimplencia_pct']
    const corpo = linhas.map((l) => cab.map((c) => String(l[c as keyof LinhaBi] ?? '')).join(';'))
    const csv = [`negocio;${linhas[0]?.negocio ?? ''}`, cab.join(';'), ...corpo].join('\n')
    const url = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }))
    const a = document.createElement('a')
    a.href = url
    a.download = `gerencial-${(linhas[0]?.negocio ?? 'negocio').toLowerCase().replace(/\W+/g, '-')}-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <>
      <CabecalhoPagina titulo="Gerencial" descricao="Churn, ticket médio, inadimplência, MRR e desempenho — em tempo real"
        acoes={
          <span className="flex items-center gap-2">
            <select aria-label="Negócio" value={negocioAtual} onChange={(e) => setNegocioId(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
              {(negocios.data ?? []).filter((n) => n.ativo).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
            </select>
            <Botao variante="secundario" onClick={exportarCsv} disabled={linhas.length === 0}>Exportar CSV</Botao>
          </span>
        } />

      {bi.isPending && <Carregando texto="Calculando…" />}
      {bi.error != null && <Alerta tipo="erro">{mensagemDeErro(bi.error)}</Alerta>}

      {bi.isSuccess && atual && (
        <div className="space-y-6">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-6">
            <Indicador rotulo="Clientes ativos" valor={String(atual.ativos_fim)} detalhe={`${atual.novos} novo(s) no mês`} />
            <Indicador rotulo="MRR" valor={formatarMoeda(atual.mrr)} detalhe="receita recorrente mensal" />
            <Indicador rotulo="Ticket médio" valor={formatarMoeda(atual.ticket_medio)} />
            <Indicador rotulo="Churn do mês" valor={`${atual.churn_pct}%`} detalhe={`${atual.cancelamentos} cancelamento(s)`} alerta={atual.churn_pct > 3} />
            <Indicador rotulo="Inadimplência" valor={`${atual.inadimplencia_pct}%`} detalhe={`${formatarMoeda(atual.vencido_aberto)} vencido em aberto`} alerta={atual.inadimplencia_pct > 10} />
            <Indicador rotulo="Payback médio" valor={paybackMedio != null ? `${paybackMedio.toFixed(1)} meses` : '—'} detalhe={`${paybackNegocio.length} contrato(s) com instalação`} />
          </div>

          <Cartao className="p-0">
            <div className="border-b border-line px-6 py-3"><h2 className="text-sm font-semibold">Últimos 13 meses</h2></div>
            <div className="overflow-x-auto"><table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line">
                <th className="px-4 py-2 font-medium">Mês</th><th className="px-4 py-2 text-right font-medium">Novos</th><th className="px-4 py-2 text-right font-medium">Cancel.</th>
                <th className="px-4 py-2 text-right font-medium">Ativos</th><th className="px-4 py-2 text-right font-medium">Churn</th><th className="px-4 py-2 text-right font-medium">MRR</th>
                <th className="px-4 py-2 text-right font-medium">Ticket</th><th className="px-4 py-2 text-right font-medium">Previsto</th><th className="px-4 py-2 text-right font-medium">Recebido</th>
                <th className="px-4 py-2 text-right font-medium">Inadimpl.</th>
              </tr></thead>
              <tbody>
                {[...linhas].reverse().map((l) => (
                  <tr key={l.mes} className="border-b border-line last:border-0">
                    <td className="px-4 py-2 tabular-nums">{l.mes.slice(5)}/{l.mes.slice(0, 4)}</td>
                    <td className="px-4 py-2 text-right tabular-nums text-green-700">{l.novos || ''}</td>
                    <td className="px-4 py-2 text-right tabular-nums text-red-700">{l.cancelamentos || ''}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{l.ativos_fim}</td>
                    <td className={`px-4 py-2 text-right tabular-nums ${l.churn_pct > 3 ? 'text-red-700' : ''}`}>{l.churn_pct}%</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(l.mrr)}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(l.ticket_medio)}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(l.previsto)}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatarMoeda(l.recebido)}</td>
                    <td className={`px-4 py-2 text-right tabular-nums ${l.inadimplencia_pct > 10 ? 'font-semibold text-red-700' : ''}`}>{l.inadimplencia_pct}%</td>
                  </tr>
                ))}
              </tbody>
            </table></div>
          </Cartao>

          <Cartao className="p-0">
            <div className="border-b border-line px-6 py-3"><h2 className="text-sm font-semibold">Técnicos (chamados encerrados nos últimos 90 dias)</h2></div>
            {desempenho.length === 0 ? <p className="px-6 py-8 text-center text-sm text-ink-muted">Sem técnicos neste negócio.</p> : (
              <ul className="divide-y divide-line text-sm">
                {desempenho.map((d) => (
                  <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 px-6 py-3">
                    <span className="font-medium">{d.nome}</span>
                    <span className="text-ink-muted">{d.chamados} chamado(s) · tempo médio {fmtMinutos(d.tempoMedio)} · nota {d.nota ?? '—'} · {d.retornos} retorno(s)</span>
                  </li>
                ))}
              </ul>
            )}
          </Cartao>
        </div>
      )}
    </>
  )
}
