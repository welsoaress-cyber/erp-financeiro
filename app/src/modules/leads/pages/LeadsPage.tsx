import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { BarraFiltros, CampoBusca, ContagemFiltro, SelectFiltro } from '../../../core/ui/Filtros'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData } from '../../../core/formatos'
import { formatarTelefone } from '../../pessoas/tipos'
import { useNegocios } from '../../negocios/api'
import { usePlanos } from '../../contratos/api'
import { useConverterLead, useCriarLead, useLeads } from '../api'
import { FormularioLead } from '../components/FormularioLead'
import { DetalheLead } from '../components/DetalheLead'
import { ORIGENS_LEAD, ROTULO_ORIGEM_LEAD, ROTULO_STATUS_LEAD, STATUS_LEAD, type Lead, type StatusLead } from '../tipos'

const TOM_STATUS: Record<StatusLead, 'ok' | 'alerta' | 'neutro' | 'info'> = { novo: 'info', contatado: 'info', qualificado: 'alerta', negociando: 'alerta', fechado: 'ok', perdido: 'neutro' }

type Edicao = { modo: 'novo' } | { modo: 'ver'; id: string } | null

export function LeadsPage() {
  const leads = useLeads()
  const negocios = useNegocios()
  const planos = usePlanos()
  const criar = useCriarLead()
  const converter = useConverterLead()
  const navegar = useNavigate()

  const [edicao, setEdicao] = useState<Edicao>(null)
  const [busca, setBusca] = useState('')
  const [filtroNegocio, setFiltroNegocio] = useState('')
  const [filtroStatus, setFiltroStatus] = useState<StatusLead | ''>('')
  const [filtroOrigem, setFiltroOrigem] = useState<Lead['origem'] | ''>('')

  const nomeNegocio = useMemo(() => new Map((negocios.data ?? []).map((n) => [n.id, n.nome])), [negocios.data])
  const nomePlano = useMemo(() => new Map((planos.data ?? []).map((p) => [p.id, p.nome])), [planos.data])

  const termo = busca.trim().toLowerCase()
  const lista = (leads.data ?? []).filter((l) => {
    if (filtroNegocio && l.negocio_id !== filtroNegocio) return false
    if (filtroStatus && l.status !== filtroStatus) return false
    if (filtroOrigem && l.origem !== filtroOrigem) return false
    if (!termo) return true
    return l.nome.toLowerCase().includes(termo) || l.telefone.includes(termo)
  })
  const leadVisto = edicao?.modo === 'ver' ? (leads.data ?? []).find((l) => l.id === edicao.id) : undefined

  // dashboard: contagem por etapa, taxa de conversão, tempo médio de conversão, origem
  const base = leads.data ?? []
  const porEtapa = STATUS_LEAD.map((s) => ({ status: s, total: base.filter((l) => l.status === s).length }))
  const convertidos = base.filter((l) => l.convertido_pessoa_id)
  const taxaConversao = base.length > 0 ? (convertidos.length / base.length) * 100 : 0
  const tempoMedioDias = convertidos.length > 0
    ? convertidos.reduce((soma, l) => soma + (new Date(l.convertido_em ?? l.atualizado_em).getTime() - new Date(l.criado_em).getTime()) / 86400000, 0) / convertidos.length
    : null
  const porOrigem = ORIGENS_LEAD.map((o) => ({ origem: o, total: base.filter((l) => l.origem === o).length })).filter((x) => x.total > 0)

  function fechar() { criar.reset(); converter.reset(); setEdicao(null) }

  function converterLead(lead: Lead) {
    converter.mutate(lead.id, {
      onSuccess: (pessoa) => navegar(`/contratos?novo=1&negocio=${lead.negocio_id}&pessoa=${pessoa.id}${lead.plano_interesse_id ? `&plano=${lead.plano_interesse_id}` : ''}`),
    })
  }

  const carregando = leads.isPending || negocios.isPending || planos.isPending
  const erro = leads.error ?? negocios.error ?? planos.error

  return (
    <>
      <CabecalhoPagina titulo="Leads" descricao="Captação, funil e conversão de leads em clientes" acoes={<Botao onClick={() => setEdicao({ modo: 'novo' })}>Novo lead</Botao>} />
      {carregando && <Carregando texto="Carregando leads…" />}
      {erro && <Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(erro)}</Alerta>}

      {leads.isSuccess && negocios.isSuccess && planos.isSuccess && (
        <div className="space-y-6">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Cartao className="p-5">
              <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">Leads por etapa</p>
              <ul className="mt-2 space-y-1 text-sm">
                {porEtapa.map((e) => (
                  <li key={e.status} className="flex items-center justify-between"><span className="text-ink-muted">{ROTULO_STATUS_LEAD[e.status]}</span><span className="font-medium tabular-nums">{e.total}</span></li>
                ))}
              </ul>
            </Cartao>
            <Cartao className="p-5">
              <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">Taxa de conversão</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-green-700">{taxaConversao.toFixed(0)}%</p>
              <p className="mt-1 text-xs text-ink-muted">{convertidos.length} de {base.length} lead(s)</p>
            </Cartao>
            <Cartao className="p-5">
              <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">Tempo médio de conversão</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums">{tempoMedioDias === null ? '—' : `${tempoMedioDias.toFixed(1)} dia(s)`}</p>
            </Cartao>
            <Cartao className="p-5">
              <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">Origem dos leads</p>
              <ul className="mt-2 space-y-1 text-sm">
                {porOrigem.length === 0 && <li className="text-ink-muted">—</li>}
                {porOrigem.map((o) => (
                  <li key={o.origem} className="flex items-center justify-between"><span className="text-ink-muted">{ROTULO_ORIGEM_LEAD[o.origem]}</span><span className="font-medium tabular-nums">{o.total}</span></li>
                ))}
              </ul>
            </Cartao>
          </div>

          <Cartao className="p-0">
            <BarraFiltros>
              <CampoBusca valor={busca} aoMudar={setBusca} rotulo="Buscar por nome ou telefone" />
              <ContagemFiltro visiveis={lista.length} total={base.length} singular="lead" plural="leads" />
              <SelectFiltro valor={filtroNegocio} aoMudar={setFiltroNegocio} rotulo="Filtrar por negócio">
                <option value="">Todos os negócios</option>
                {(negocios.data ?? []).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
              </SelectFiltro>
              <SelectFiltro valor={filtroStatus} aoMudar={(v) => setFiltroStatus(v as StatusLead | '')} rotulo="Filtrar por etapa">
                <option value="">Todas as etapas</option>
                {STATUS_LEAD.map((s) => <option key={s} value={s}>{ROTULO_STATUS_LEAD[s]}</option>)}
              </SelectFiltro>
              <SelectFiltro valor={filtroOrigem} aoMudar={(v) => setFiltroOrigem(v as Lead['origem'] | '')} rotulo="Filtrar por origem">
                <option value="">Todas as origens</option>
                {ORIGENS_LEAD.map((o) => <option key={o} value={o}>{ROTULO_ORIGEM_LEAD[o]}</option>)}
              </SelectFiltro>
            </BarraFiltros>
            {lista.length === 0 ? (
              <div className="flex flex-col items-center gap-3 py-16 text-center">
                <p className="text-sm font-medium">Nenhum lead encontrado</p>
                <Botao onClick={() => setEdicao({ modo: 'novo' })}>Novo lead</Botao>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                    <tr className="border-b border-line">
                      <th className="px-6 py-3 font-medium">Nome</th>
                      <th className="px-6 py-3 font-medium">Contato</th>
                      <th className="px-6 py-3 font-medium">Negócio</th>
                      <th className="px-6 py-3 font-medium">Origem</th>
                      <th className="px-6 py-3 font-medium">Etapa</th>
                      <th className="px-6 py-3 font-medium">Criado em</th>
                    </tr>
                  </thead>
                  <tbody>
                    {lista.map((l) => (
                      <tr key={l.id} onClick={() => setEdicao({ modo: 'ver', id: l.id })} className="cursor-pointer border-b border-line last:border-0 hover:bg-surface">
                        <td className="px-6 py-3 font-medium">{l.nome}</td>
                        <td className="px-6 py-3 text-ink-muted">{formatarTelefone(l.telefone)}</td>
                        <td className="px-6 py-3 text-ink-muted">{nomeNegocio.get(l.negocio_id) ?? '—'}</td>
                        <td className="px-6 py-3 text-ink-muted">{ROTULO_ORIGEM_LEAD[l.origem]}</td>
                        <td className="px-6 py-3"><Distintivo tom={TOM_STATUS[l.status]}>{ROTULO_STATUS_LEAD[l.status]}</Distintivo></td>
                        <td className="px-6 py-3 text-ink-muted">{formatarData(l.criado_em.slice(0, 10))}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Cartao>
        </div>
      )}

      <Modal aberto={edicao !== null} aoFechar={fechar} titulo={edicao?.modo === 'novo' ? 'Novo lead' : leadVisto ? leadVisto.nome : 'Lead'}>
        {edicao?.modo === 'novo' && (
          <FormularioLead negocios={negocios.data ?? []} planos={planos.data ?? []} salvando={criar.isPending} erro={criar.error ? mensagemDeErro(criar.error) : null} aoSalvar={(d) => criar.mutate(d, { onSuccess: fechar })} aoCancelar={fechar} />
        )}
        {leadVisto && (
          <DetalheLead
            lead={leadVisto}
            nomeNegocio={nomeNegocio.get(leadVisto.negocio_id) ?? '—'}
            nomePlano={leadVisto.plano_interesse_id ? nomePlano.get(leadVisto.plano_interesse_id) ?? '—' : null}
            aoConverter={() => converterLead(leadVisto)}
            convertendo={converter.isPending}
            erroConverter={converter.error ? mensagemDeErro(converter.error) : null}
          />
        )}
      </Modal>
    </>
  )
}
