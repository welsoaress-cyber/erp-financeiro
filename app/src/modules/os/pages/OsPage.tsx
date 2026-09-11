import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { Carregando } from '../../../core/ui/Carregando'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda, hojeISO } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useContratos } from '../../contratos/api'
import { codigoContrato } from '../../contratos/tipos'
import { useCtos } from '../../ftth/api'
import { useEstoqueItens } from '../../estoque/api'
import { useBolsaResumo, useOrdens, useSalvarTecnico, useTecnicos } from '../api'
import { fmtMinutos, ROTULO_STATUS_OS, ROTULO_TIPO_OS, type OrdemServico, type Tecnico } from '../tipos'
import { NovoChamado } from '../components/NovoChamado'
import { DetalheChamado } from '../components/DetalheChamado'
import { BolsaTecnico } from '../components/BolsaTecnico'

type Aba = 'dashboard' | 'chamados' | 'agenda' | 'tecnicos'
const TOM_STATUS = { aberto: 'info', em_atendimento: 'ok', pausado: 'alerta', encerrado: 'neutro', cancelado: 'neutro' } as const
const ABERTOS: OrdemServico['status'][] = ['aberto', 'em_atendimento', 'pausado']

function horasDesde(iso: string) { return (Date.now() - new Date(iso).getTime()) / 3_600_000 }

export function OsPage() {
  const negocios = useNegocios()
  const ordens = useOrdens()
  const tecnicos = useTecnicos()
  const bolsas = useBolsaResumo()
  const pessoas = usePessoas()
  const contratos = useContratos()
  const ctos = useCtos()
  const itens = useEstoqueItens()
  const salvarTecnico = useSalvarTecnico()

  const [aba, setAba] = useState<Aba>('dashboard')
  const [negocioId, setNegocioId] = useState('')
  const [filtroStatus, setFiltroStatus] = useState('')
  const [filtroTecnico, setFiltroTecnico] = useState('')
  const [busca, setBusca] = useState('')
  const [modal, setModal] = useState<'novo' | 'tecnico' | null>(null)
  const [osVista, setOsVista] = useState<string | null>(null)
  const [tecnicoBolsa, setTecnicoBolsa] = useState<Tecnico | null>(null)
  const [tecnicoEdicao, setTecnicoEdicao] = useState<Tecnico | null>(null)
  const [nomeTec, setNomeTec] = useState(''); const [foneTec, setFoneTec] = useState('')

  const servnet = (negocios.data ?? []).find((n) => n.nome.toLowerCase().includes('servnet')) ?? (negocios.data ?? [])[0]
  const negocioAtual = negocioId || servnet?.id || ''
  const lista = (ordens.data ?? []).filter((o) => o.negocio_id === negocioAtual)
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const nomeTecnico = useMemo(() => new Map((tecnicos.data ?? []).map((t) => [t.id, t.nome])), [tecnicos.data])
  const nomeCto = useMemo(() => new Map((ctos.data ?? []).map((c) => [c.id, c.codigo])), [ctos.data])
  const nomeItem = useMemo(() => new Map((itens.data ?? []).map((i) => [i.id, `${i.codigo} · ${i.nome}`])), [itens.data])
  const rotuloContrato = (id: string | null) => { const c = (contratos.data ?? []).find((x) => x.id === id); return c ? codigoContrato(c) : null }

  const abertas = lista.filter((o) => ABERTOS.includes(o.status))
  const encerradasMes = lista.filter((o) => o.status === 'encerrado' && o.data_fim && o.data_fim.slice(0, 7) === hojeISO().slice(0, 7))
  // alertas: urgente sem início > 4h, pausado > 24h, técnico com 5+ abertos, bolsa negativa/abaixo do mínimo
  const urgentes = abertas.filter((o) => o.prioridade === 'urgente' && o.status === 'aberto' && horasDesde(o.criado_em) > 4)
  const pausados = abertas.filter((o) => o.status === 'pausado' && o.pausado_em && horasDesde(o.pausado_em) > 24)
  const sobrecarga = (tecnicos.data ?? []).filter((t) => t.negocio_id === negocioAtual && abertas.filter((o) => o.tecnico_id === t.id).length >= 5)
  const bolsasAlerta = (bolsas.data ?? []).filter((b) => b.negocio_id === negocioAtual && (b.itens_negativos > 0 || b.itens_abaixo_minimo > 0))
  const alertas = [
    ...urgentes.map((o) => `Urgente sem atendimento: ${o.numero} (${Math.floor(horasDesde(o.criado_em))}h)`),
    ...pausados.map((o) => `Pausado há mais de 1 dia: ${o.numero}`),
    ...sobrecarga.map((t) => `${t.nome} com ${abertas.filter((o) => o.tecnico_id === t.id).length} chamados abertos`),
    ...bolsasAlerta.map((b) => `Bolsa de ${b.tecnico}: ${b.itens_negativos > 0 ? `${b.itens_negativos} item(ns) negativo(s)` : `${b.itens_abaixo_minimo} abaixo do mínimo`}`),
  ]

  const filtrada = lista.filter((o) =>
    (!filtroStatus || o.status === filtroStatus) &&
    (!filtroTecnico || o.tecnico_id === filtroTecnico) &&
    (!busca.trim() || o.numero.toLowerCase().includes(busca.toLowerCase()) || (nomePessoa.get(o.pessoa_id ?? '') ?? '').toLowerCase().includes(busca.toLowerCase())))

  // agenda: próximos 7 dias, agendadas e não finalizadas
  const dias = Array.from({ length: 7 }, (_, i) => { const d = new Date(); d.setDate(d.getDate() + i); return d.toISOString().slice(0, 10) })
  const agendadasDe = (dia: string) => abertas.filter((o) => o.data_agendada === dia).sort((a, b) => (a.hora_agendada ?? '').localeCompare(b.hora_agendada ?? ''))

  const osAtual = (ordens.data ?? []).find((o) => o.id === osVista) ?? null
  const tecnicosNegocio = (tecnicos.data ?? []).filter((t) => t.negocio_id === negocioAtual)

  return (
    <>
      <CabecalhoPagina titulo="Ordens de Serviço" descricao="Chamados técnicos, bolsa de materiais e comissões"
        acoes={<span className="flex gap-2"><Botao variante="secundario" onClick={() => { setTecnicoEdicao(null); setNomeTec(''); setFoneTec(''); setModal('tecnico') }}>Novo técnico</Botao><Botao onClick={() => setModal('novo')}>Novo chamado</Botao></span>} />

      {alertas.length > 0 && (
        <div className="mb-4"><Alerta tipo="erro" titulo={`${alertas.length} alerta(s)`}>{alertas.slice(0, 5).join(' · ')}</Alerta></div>
      )}

      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div role="tablist" className="flex gap-1 rounded-md border border-line p-1 text-sm">
          {(['dashboard', 'chamados', 'agenda', 'tecnicos'] as Aba[]).map((a) => (
            <button key={a} role="tab" aria-selected={aba === a} onClick={() => setAba(a)} className={`rounded px-3 py-1.5 ${aba === a ? 'bg-brand-600 text-white' : 'text-ink-muted hover:text-ink'}`}>
              {a === 'dashboard' ? 'Dashboard' : a === 'chamados' ? 'Chamados' : a === 'agenda' ? 'Agenda' : 'Técnicos'}
            </button>
          ))}
        </div>
        <select aria-label="Negócio" value={negocioAtual} onChange={(e) => setNegocioId(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
          {(negocios.data ?? []).filter((n) => n.ativo).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
        </select>
      </div>

      {ordens.isPending && <Carregando />}
      {ordens.error != null && <Alerta tipo="erro">{mensagemDeErro(ordens.error)}</Alerta>}

      {aba === 'dashboard' && ordens.isSuccess && (
        <div className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">Abertos</p><p className="mt-1 text-xl font-semibold">{abertas.filter((o) => o.status === 'aberto').length}</p></Cartao>
            <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">Em atendimento / pausados</p><p className="mt-1 text-xl font-semibold">{abertas.filter((o) => o.status === 'em_atendimento').length} / {abertas.filter((o) => o.status === 'pausado').length}</p></Cartao>
            <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">Encerrados no mês</p><p className="mt-1 text-xl font-semibold">{encerradasMes.length}</p><p className="text-xs text-ink-muted">{encerradasMes.filter((o) => o.retorno).length} retorno(s)</p></Cartao>
            <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">Valor nas bolsas</p><p className="mt-1 text-xl font-semibold tabular-nums">{formatarMoeda((bolsas.data ?? []).filter((b) => b.negocio_id === negocioAtual).reduce((s, b) => s + b.valor_em_campo, 0))}</p><p className="text-xs text-ink-muted">material em campo</p></Cartao>
          </div>
          <Cartao className="p-0">
            <h2 className="border-b border-line px-6 py-3 text-sm font-semibold">Tempo médio por técnico (encerrados no mês)</h2>
            <ul className="divide-y divide-line text-sm">
              {tecnicosNegocio.map((t) => {
                const done = encerradasMes.filter((o) => o.tecnico_id === t.id && o.tempo_total_minutos != null)
                const media = done.length ? Math.round(done.reduce((s, o) => s + (o.tempo_total_minutos ?? 0), 0) / done.length) : null
                return (
                  <li key={t.id} className="flex items-center justify-between px-6 py-3">
                    <span className="font-medium">{t.nome}{!t.ativo && <span className="ml-2 text-xs font-normal text-ink-muted">(inativo)</span>}</span>
                    <span className="text-ink-muted">{done.length} encerrado(s) · média {fmtMinutos(media)} · {abertas.filter((o) => o.tecnico_id === t.id).length} em aberto</span>
                  </li>
                )
              })}
              {tecnicosNegocio.length === 0 && <li className="px-6 py-8 text-center text-ink-muted">Cadastre o primeiro técnico.</li>}
            </ul>
          </Cartao>
        </div>
      )}

      {aba === 'chamados' && ordens.isSuccess && (
        <Cartao className="p-0">
          <div className="flex flex-wrap items-center gap-2 border-b border-line px-4 py-3 text-sm">
            <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar número ou cliente…" className="h-9 w-56 rounded-md border border-line bg-white px-3" />
            <select aria-label="Status" value={filtroStatus} onChange={(e) => setFiltroStatus(e.target.value)} className="h-9 rounded-md border border-line bg-white px-2">
              <option value="">Todos</option>{Object.entries(ROTULO_STATUS_OS).map(([v, r]) => <option key={v} value={v}>{r}</option>)}
            </select>
            <select aria-label="Técnico" value={filtroTecnico} onChange={(e) => setFiltroTecnico(e.target.value)} className="h-9 rounded-md border border-line bg-white px-2">
              <option value="">Todos os técnicos</option>{tecnicosNegocio.map((t) => <option key={t.id} value={t.id}>{t.nome}</option>)}
            </select>
            <span className="text-ink-muted">{filtrada.length} chamado(s)</span>
          </div>
          {filtrada.length === 0 ? <p className="px-6 py-12 text-center text-sm text-ink-muted">Nenhum chamado. Clique em "Novo chamado".</p> : (
            <div className="overflow-x-auto"><table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Número</th><th className="px-4 py-2 font-medium">Tipo</th><th className="px-4 py-2 font-medium">Cliente</th><th className="px-4 py-2 font-medium">Técnico</th><th className="px-4 py-2 font-medium">Agendado</th><th className="px-4 py-2 font-medium">Status</th><th className="px-4 py-2"></th></tr></thead>
              <tbody>
                {filtrada.map((o) => (
                  <tr key={o.id} className="cursor-pointer border-b border-line last:border-0 hover:bg-surface" onClick={() => setOsVista(o.id)}>
                    <td className="whitespace-nowrap px-4 py-2 font-mono text-xs">{o.numero}{o.retorno && <span className="ml-1 text-red-700" title="Retorno em até 7 dias">↺</span>}</td>
                    <td className="px-4 py-2">{ROTULO_TIPO_OS[o.tipo]}{o.prioridade === 'urgente' && <span className="ml-1 font-semibold text-red-700">!</span>}</td>
                    <td className="px-4 py-2">{nomePessoa.get(o.pessoa_id ?? '') ?? <span className="text-ink-muted">Rede</span>}</td>
                    <td className="px-4 py-2 text-ink-muted">{nomeTecnico.get(o.tecnico_id ?? '') ?? '—'}</td>
                    <td className="whitespace-nowrap px-4 py-2 tabular-nums">{o.data_agendada ? `${formatarData(o.data_agendada)} ${o.hora_agendada?.slice(0, 5) ?? ''}` : '—'}</td>
                    <td className="px-4 py-2"><Distintivo tom={TOM_STATUS[o.status]}>{ROTULO_STATUS_OS[o.status]}</Distintivo></td>
                    <td className="px-4 py-2 text-right text-brand-700">Abrir</td>
                  </tr>
                ))}
              </tbody>
            </table></div>
          )}
        </Cartao>
      )}

      {aba === 'agenda' && ordens.isSuccess && (
        <div className="grid gap-3 md:grid-cols-4 lg:grid-cols-7">
          {dias.map((dia) => (
            <Cartao key={dia} className="p-3">
              <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-muted">{new Date(dia + 'T12:00:00').toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' })}</p>
              {agendadasDe(dia).length === 0 && <p className="text-xs text-ink-muted">—</p>}
              {agendadasDe(dia).map((o) => (
                <button key={o.id} type="button" onClick={() => setOsVista(o.id)} className="mb-1 block w-full rounded border border-line px-2 py-1 text-left text-xs hover:bg-surface">
                  <span className="font-medium tabular-nums">{o.hora_agendada?.slice(0, 5)}</span> {nomePessoa.get(o.pessoa_id ?? '') ?? 'Rede'}
                  <span className="block text-ink-muted">{nomeTecnico.get(o.tecnico_id ?? '') ?? '—'} · {ROTULO_TIPO_OS[o.tipo]}</span>
                </button>
              ))}
            </Cartao>
          ))}
        </div>
      )}

      {aba === 'tecnicos' && (
        <Cartao className="p-0">
          <ul className="divide-y divide-line text-sm">
            {tecnicosNegocio.map((t) => {
              const b = (bolsas.data ?? []).find((x) => x.tecnico_id === t.id)
              return (
                <li key={t.id} className="flex flex-wrap items-center justify-between gap-2 px-6 py-3">
                  <span>
                    <span className="font-medium">{t.nome}</span>{!t.ativo && <span className="ml-2 text-xs text-ink-muted">(inativo)</span>}
                    <span className="ml-2 text-xs text-ink-muted">{t.telefone ?? ''} · bolsa {formatarMoeda(b?.valor_em_campo ?? 0)}{b && b.itens_negativos > 0 ? ` · ${b.itens_negativos} negativo(s)` : ''}</span>
                  </span>
                  <span className="flex gap-3 text-xs">
                    <button type="button" className="text-brand-700 hover:underline" onClick={() => setTecnicoBolsa(t)}>Bolsa</button>
                    <button type="button" className="text-brand-700 hover:underline" onClick={() => { setTecnicoEdicao(t); setNomeTec(t.nome); setFoneTec(t.telefone ?? ''); setModal('tecnico') }}>Editar</button>
                  </span>
                </li>
              )
            })}
            {tecnicosNegocio.length === 0 && <li className="px-6 py-10 text-center text-ink-muted">Nenhum técnico. Clique em "Novo técnico" — o login dele chega na próxima etapa.</li>}
          </ul>
        </Cartao>
      )}

      <Modal aberto={modal === 'novo'} aoFechar={() => setModal(null)} largura="lg" titulo="Novo chamado">
        {modal === 'novo' && negocioAtual && <NovoChamado negocioId={negocioAtual} aoFechar={() => setModal(null)} />}
      </Modal>

      <Modal aberto={modal === 'tecnico'} aoFechar={() => { setModal(null); salvarTecnico.reset() }} largura="md" titulo={tecnicoEdicao ? 'Editar técnico' : 'Novo técnico'}>
        {modal === 'tecnico' && (
          <div className="space-y-4">
            {salvarTecnico.error != null && <Alerta tipo="erro">{mensagemDeErro(salvarTecnico.error)}</Alerta>}
            <Campo rotulo="Nome" value={nomeTec} onChange={(e) => setNomeTec(e.target.value)} maxLength={80} />
            <Campo rotulo="Telefone (opcional)" value={foneTec} onChange={(e) => setFoneTec(e.target.value)} maxLength={20} />
            {!tecnicoEdicao && <p className="text-xs text-ink-muted">O técnico também vira um cadastro em Pessoas (fornecedor das comissões). Login próprio chega na etapa 29B.</p>}
            <div className="flex justify-end gap-2">
              {tecnicoEdicao && <Botao variante="secundario" carregando={salvarTecnico.isPending} onClick={() => salvarTecnico.mutate({ id: tecnicoEdicao.id, negocio_id: tecnicoEdicao.negocio_id, nome: nomeTec.trim(), telefone: foneTec.trim() || null, ativo: !tecnicoEdicao.ativo }, { onSuccess: () => setModal(null) })}>{tecnicoEdicao.ativo ? 'Desativar' : 'Reativar'}</Botao>}
              <Botao disabled={nomeTec.trim().length < 2} carregando={salvarTecnico.isPending} onClick={() => salvarTecnico.mutate({ id: tecnicoEdicao?.id, negocio_id: tecnicoEdicao?.negocio_id ?? negocioAtual, nome: nomeTec.trim(), telefone: foneTec.trim() || null, ativo: tecnicoEdicao?.ativo ?? true }, { onSuccess: () => setModal(null) })}>{tecnicoEdicao ? 'Salvar' : 'Cadastrar'}</Botao>
            </div>
          </div>
        )}
      </Modal>

      <Modal aberto={osAtual !== null} aoFechar={() => setOsVista(null)} largura="xl" titulo={osAtual ? `Chamado ${osAtual.numero}` : ''}>
        {osAtual && (
          <DetalheChamado key={osAtual.id + osAtual.status + String(osAtual.remarcacao_data ?? '') + String(osAtual.avaliacao_resolvido ?? '') + String(osAtual.comissao_lancamento_id ?? '') + String(osAtual.data_agendada ?? '') + (osAtual.hora_agendada ?? '')} os={osAtual}
            nomes={{ pessoa: osAtual.pessoa_id ? nomePessoa.get(osAtual.pessoa_id) ?? null : null, tecnico: osAtual.tecnico_id ? nomeTecnico.get(osAtual.tecnico_id) ?? null : null, cto: osAtual.cto_id ? nomeCto.get(osAtual.cto_id) ?? null : null, contrato: rotuloContrato(osAtual.contrato_id), item: nomeItem }}
            aoFechar={() => setOsVista(null)} />
        )}
      </Modal>

      <Modal aberto={tecnicoBolsa !== null} aoFechar={() => setTecnicoBolsa(null)} largura="xl" titulo={tecnicoBolsa ? `Bolsa de ${tecnicoBolsa.nome}` : ''}>
        {tecnicoBolsa && <BolsaTecnico tecnico={tecnicoBolsa} aoFechar={() => setTecnicoBolsa(null)} />}
      </Modal>
    </>
  )
}
