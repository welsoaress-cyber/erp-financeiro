import { useMemo, useState } from 'react'
import { Alerta } from '../../core/ui/Alerta'
import { Modal } from '../../core/ui/Modal'
import { Distintivo } from '../../core/ui/Distintivo'
import { Carregando } from '../../core/ui/Carregando'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { ROTULO_STATUS_OS, ROTULO_TIPO_OS, type OrdemServico } from '../../modules/os/tipos'
import { useMeusChamados } from '../api'
import { DetalheTecnico, TOM_STATUS } from './TecnicoChamadosPage'

const DIAS = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo']
const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
const inicioSemana = (d: Date) => { const dia = (d.getDay() + 6) % 7; const r = new Date(d); r.setDate(d.getDate() - dia); r.setHours(0, 0, 0, 0); return r }

/** Agenda semanal do técnico — grade simples (sem lib de calendário), só o que já está agendado. */
export function TecnicoAgendaPage() {
  const chamados = useMeusChamados()
  const [base, setBase] = useState(() => new Date())
  const [vistoId, setVistoId] = useState<string | null>(null)
  const visto = (chamados.data ?? []).find((o) => o.id === vistoId) ?? null

  const dias = useMemo(() => {
    const ini = inicioSemana(base)
    return Array.from({ length: 7 }, (_, i) => { const d = new Date(ini); d.setDate(ini.getDate() + i); return d })
  }, [base])

  const porDia = useMemo(() => {
    const m = new Map<string, OrdemServico[]>()
    for (const o of chamados.data ?? []) {
      if (!o.data_agendada || o.status === 'encerrado' || o.status === 'cancelado') continue
      const lista = m.get(o.data_agendada) ?? []
      lista.push(o)
      m.set(o.data_agendada, lista)
    }
    for (const lista of m.values()) lista.sort((a, b) => (a.hora_agendada ?? '').localeCompare(b.hora_agendada ?? ''))
    return m
  }, [chamados.data])

  if (chamados.isPending) return <Carregando />
  if (chamados.error != null) return <Alerta tipo="erro">{mensagemDeErro(chamados.error)}</Alerta>

  const hoje = iso(new Date())
  const rotuloSemana = `${dias[0].toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })} – ${dias[6].toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })}`

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <button type="button" aria-label="Semana anterior" onClick={() => setBase((d) => { const n = new Date(d); n.setDate(d.getDate() - 7); return n })} className="rounded-md border border-line bg-white px-3 py-1.5 text-sm">‹</button>
        <span className="text-sm font-semibold">{rotuloSemana}</span>
        <button type="button" aria-label="Próxima semana" onClick={() => setBase((d) => { const n = new Date(d); n.setDate(d.getDate() + 7); return n })} className="rounded-md border border-line bg-white px-3 py-1.5 text-sm">›</button>
      </div>

      {dias.map((d) => {
        const diaIso = iso(d)
        const lista = porDia.get(diaIso) ?? []
        return (
          <div key={diaIso}>
            <h2 className={`mb-2 text-sm font-semibold ${diaIso === hoje ? 'text-brand-700' : 'text-ink-muted'}`}>
              {DIAS[(d.getDay() + 6) % 7]} · {d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })}{diaIso === hoje ? ' · hoje' : ''}
            </h2>
            {lista.length === 0 ? (
              <p className="rounded-md border border-dashed border-line px-3 py-2 text-xs text-ink-muted">Nada agendado.</p>
            ) : (
              <div className="space-y-2">
                {lista.map((o) => (
                  <button key={o.id} type="button" onClick={() => setVistoId(o.id)} className="block w-full rounded-lg border border-line bg-white p-3 text-left text-sm hover:border-brand-600">
                    <div className="flex items-center justify-between">
                      <span className="font-medium tabular-nums">{o.hora_agendada?.slice(0, 5) ?? '—'} · {ROTULO_TIPO_OS[o.tipo]}{o.prioridade === 'urgente' && <span className="ml-1 text-red-700">!</span>}</span>
                      <Distintivo tom={TOM_STATUS[o.status]}>{ROTULO_STATUS_OS[o.status]}</Distintivo>
                    </div>
                    <p className="mt-1 line-clamp-1 text-ink-muted">{o.descricao}</p>
                  </button>
                ))}
              </div>
            )}
          </div>
        )
      })}

      <Modal aberto={visto !== null} aoFechar={() => setVistoId(null)} largura="md" titulo={visto?.numero ?? ''}>
        {visto && <DetalheTecnico key={visto.id + visto.status + String(visto.data_agendada ?? '')} os={visto} aoFechar={() => setVistoId(null)} />}
      </Modal>
    </div>
  )
}
