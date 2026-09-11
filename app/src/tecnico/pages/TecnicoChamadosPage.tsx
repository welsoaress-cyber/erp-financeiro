import { useState } from 'react'
import { Alerta } from '../../core/ui/Alerta'
import { Botao } from '../../core/ui/Botao'
import { Campo } from '../../core/ui/Campo'
import { Selecao } from '../../core/ui/Selecao'
import { Modal } from '../../core/ui/Modal'
import { Distintivo } from '../../core/ui/Distintivo'
import { Carregando } from '../../core/ui/Carregando'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { formatarData, hojeISO } from '../../core/formatos'
import { fmtQtd } from '../../modules/estoque/tipos'
import { ROTULO_DIAGNOSTICO, ROTULO_STATUS_OS, ROTULO_TIPO_OS, type OrdemServico } from '../../modules/os/tipos'
import {
  useAgendar, useCiencia, useEncerrar, useEnviarFoto, useFotosOs, useInfoCliente, useIniciar, useItensDoNegocio,
  useMeusChamados, useMinhaBolsa, usePausar, useRetomar, useSolicitarRemarcacaoTec,
} from '../api'

const TOM_STATUS = { aberto: 'info', em_atendimento: 'ok', pausado: 'alerta', encerrado: 'neutro', cancelado: 'neutro' } as const

function DetalheTecnico({ os, aoFechar }: { os: OrdemServico; aoFechar: () => void }) {
  const info = useInfoCliente(os.id)
  const bolsa = useMinhaBolsa()
  const itens = useItensDoNegocio()
  const fotos = useFotosOs(os.id)
  const ciencia = useCiencia(); const agendar = useAgendar(); const remarcar = useSolicitarRemarcacaoTec()
  const iniciar = useIniciar(); const pausar = usePausar(); const retomar = useRetomar(); const encerrar = useEncerrar()
  const enviarFoto = useEnviarFoto()
  const [painel, setPainel] = useState<'nenhum' | 'agendar' | 'remarcar' | 'pausar' | 'encerrar'>('nenhum')
  const [data, setData] = useState(hojeISO()); const [hora, setHora] = useState('08:00'); const [motivo, setMotivo] = useState('')
  const [linhas, setLinhas] = useState<{ itemId: string; quantidade: string }[]>([{ itemId: '', quantidade: '' }])
  const [equips, setEquips] = useState<{ itemId: string; serie: string }[]>([])
  const [diagnostico, setDiagnostico] = useState(''); const [sinal, setSinal] = useState(''); const [obs, setObs] = useState('')
  const erro = [ciencia, agendar, remarcar, iniciar, pausar, retomar, encerrar, enviarFoto].map((m) => m.error).find((e) => e != null)
  const saldoDe = (id: string) => (bolsa.data ?? []).find((b) => b.item_id === id)?.quantidade ?? 0
  const aberto = os.status === 'aberto'; const atendendo = os.status === 'em_atendimento'; const pausado = os.status === 'pausado'
  const fechar = { onSuccess: () => setPainel('nenhum') }

  return (
    <div className="space-y-4 text-sm">
      <div className="flex items-start justify-between gap-2">
        <div>
          <p className="font-mono text-xs text-ink-muted">{os.numero}</p>
          <p className="font-semibold">{ROTULO_TIPO_OS[os.tipo]}{os.prioridade === 'urgente' && <span className="ml-2 text-red-700">URGENTE</span>}</p>
        </div>
        <Distintivo tom={TOM_STATUS[os.status]}>{ROTULO_STATUS_OS[os.status]}</Distintivo>
      </div>
      {erro != null && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}
      <p className="rounded-md bg-surface p-3">{os.descricao}</p>
      {info.data && (
        <div className="rounded-md border border-line p-3">
          <p className="font-medium">{info.data.cliente ?? 'Sem cliente (serviço de rede)'}</p>
          {info.data.endereco && <p className="text-ink-muted">{info.data.endereco}</p>}
          <p className="text-ink-muted">
            {info.data.telefone && <a className="text-brand-700 underline" href={`tel:${info.data.telefone}`}>{info.data.telefone}</a>}
            {info.data.contrato && <> · contrato {info.data.contrato}</>}{info.data.cto && <> · CTO {info.data.cto}</>}
          </p>
        </div>
      )}
      <p className="text-xs text-ink-muted">{os.data_agendada ? `Agendado para ${formatarData(os.data_agendada)} às ${os.hora_agendada?.slice(0, 5)}` : 'Ainda sem agendamento — marque dia e hora.'}{os.remarcacao_data ? ` · remarcação pedida (${formatarData(os.remarcacao_data)} ${os.remarcacao_hora?.slice(0, 5)}) aguardando aval` : ''}</p>

      <div className="grid grid-cols-2 gap-2">
        {aberto && !os.data_ciencia && <Botao variante="secundario" onClick={() => ciencia.mutate({ p_os_id: os.id })} carregando={ciencia.isPending}>Estou ciente</Botao>}
        {aberto && !os.data_agendada && <Botao onClick={() => setPainel('agendar')}>Agendar visita</Botao>}
        {aberto && os.data_agendada && !os.remarcacao_data && <Botao variante="secundario" onClick={() => setPainel('remarcar')}>Pedir remarcação</Botao>}
        {aberto && os.data_agendada && <Botao onClick={() => iniciar.mutate({ p_os_id: os.id })} carregando={iniciar.isPending}>Iniciar atendimento</Botao>}
        {atendendo && <Botao variante="secundario" onClick={() => setPainel('pausar')}>Pausar</Botao>}
        {pausado && <Botao onClick={() => retomar.mutate({ p_os_id: os.id })} carregando={retomar.isPending}>Retomar</Botao>}
        {(atendendo || pausado) && <Botao onClick={() => setPainel('encerrar')}>Encerrar</Botao>}
      </div>

      {painel === 'agendar' && (
        <div className="space-y-2 rounded-md border border-line p-3">
          <Campo rotulo="Data" type="date" value={data} onChange={(e) => setData(e.target.value)} />
          <Campo rotulo="Hora" type="time" value={hora} onChange={(e) => setHora(e.target.value)} />
          <Botao onClick={() => agendar.mutate({ p_os_id: os.id, p_data: data, p_hora: hora }, fechar)} carregando={agendar.isPending}>Confirmar agendamento</Botao>
        </div>
      )}
      {painel === 'remarcar' && (
        <div className="space-y-2 rounded-md border border-line p-3">
          <Campo rotulo="Nova data" type="date" value={data} onChange={(e) => setData(e.target.value)} />
          <Campo rotulo="Hora" type="time" value={hora} onChange={(e) => setHora(e.target.value)} />
          <Campo rotulo="Motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={300} placeholder="Ex.: faltou material" />
          <Botao disabled={motivo.trim().length < 3} onClick={() => remarcar.mutate({ p_os_id: os.id, p_data: data, p_hora: hora, p_motivo: motivo }, fechar)} carregando={remarcar.isPending}>Pedir remarcação</Botao>
          <p className="text-xs text-ink-muted">Quem abriu o chamado precisa aprovar a nova data.</p>
        </div>
      )}
      {painel === 'pausar' && (
        <div className="space-y-2 rounded-md border border-line p-3">
          <Campo rotulo="Motivo da pausa" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={300} autoFocus />
          <Botao disabled={motivo.trim().length < 3} onClick={() => pausar.mutate({ p_os_id: os.id, p_motivo: motivo }, fechar)} carregando={pausar.isPending}>Pausar</Botao>
        </div>
      )}
      {painel === 'encerrar' && (
        <div className="space-y-3 rounded-md border border-line p-3">
          <p className="font-medium">Materiais usados (saem da sua bolsa)</p>
          {linhas.map((l, i) => (
            <div key={i} className="flex items-end gap-2">
              <div className="flex-1"><Selecao rotulo={i === 0 ? 'Item' : ''} opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(itens.data ?? []).map((x) => ({ valor: x.id, rotulo: `${x.codigo} · ${x.nome} (bolsa: ${fmtQtd(saldoDe(x.id))})` }))]} value={l.itemId} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, itemId: e.target.value } : x)))} /></div>
              <input type="number" step="0.01" min="0.01" placeholder="Qtd." aria-label="Quantidade" value={l.quantidade} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, quantidade: e.target.value } : x)))} className="h-10 w-20 rounded-md border border-line bg-white px-2 text-sm" />
              <button type="button" aria-label="Remover" className="pb-2 text-ink-muted" onClick={() => setLinhas((xs) => xs.filter((_, j) => j !== i))}>×</button>
            </div>
          ))}
          <Botao variante="secundario" onClick={() => setLinhas((xs) => [...xs, { itemId: '', quantidade: '' }])}>+ Material</Botao>
          <p className="pt-1 font-medium">Equipamento instalado no cliente? Informe a série</p>
          {equips.map((l, i) => (
            <div key={i} className="flex items-end gap-2">
              <div className="flex-1"><Selecao rotulo={i === 0 ? 'Equipamento' : ''} opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(itens.data ?? []).map((x) => ({ valor: x.id, rotulo: `${x.codigo} · ${x.nome}` }))]} value={l.itemId} onChange={(e) => setEquips((xs) => xs.map((x, j) => (j === i ? { ...x, itemId: e.target.value } : x)))} /></div>
              <input placeholder="Nº de série" aria-label="Número de série" value={l.serie} onChange={(e) => setEquips((xs) => xs.map((x, j) => (j === i ? { ...x, serie: e.target.value } : x)))} className="h-10 w-32 rounded-md border border-line bg-white px-2 text-sm" />
              <button type="button" aria-label="Remover" className="pb-2 text-ink-muted" onClick={() => setEquips((xs) => xs.filter((_, j) => j !== i))}>×</button>
            </div>
          ))}
          <Botao variante="secundario" onClick={() => setEquips((xs) => [...xs, { itemId: '', serie: '' }])}>+ Equipamento (série)</Botao>
          <Selecao rotulo="O que era o problema?" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...Object.entries(ROTULO_DIAGNOSTICO).map(([v, r]) => ({ valor: v, rotulo: r }))]} value={diagnostico} onChange={(e) => setDiagnostico(e.target.value)} />
          <div className="grid grid-cols-2 gap-2">
            <Campo rotulo="Sinal (dBm)" type="number" step="0.1" value={sinal} onChange={(e) => setSinal(e.target.value)} placeholder="-18.5" />
            <Campo rotulo="Observação" value={obs} onChange={(e) => setObs(e.target.value)} maxLength={500} />
          </div>
          <div>
            <p className="mb-1 font-medium">Fotos ({(fotos.data ?? []).length}/3) — ex.: medição do sinal</p>
            <div className="flex gap-2">
              {(fotos.data ?? []).map((f) => <img key={f.id} src={f.url} alt="Foto do chamado" className="size-16 rounded-md border border-line object-cover" />)}
              {(fotos.data ?? []).length < 3 && (
                <label className="flex size-16 cursor-pointer items-center justify-center rounded-md border border-dashed border-line text-2xl text-ink-muted">
                  {enviarFoto.isPending ? '…' : '+'}
                  <input type="file" accept="image/*" capture="environment" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) enviarFoto.mutate({ os_id: os.id, arquivo: f }); e.target.value = '' }} />
                </label>
              )}
            </div>
          </div>
          <Botao carregando={encerrar.isPending} onClick={() => encerrar.mutate({
            p_os_id: os.id,
            p_itens: linhas.filter((l) => l.itemId && Number(l.quantidade.replace(',', '.')) > 0).map((l) => ({ item_id: l.itemId, quantidade: Number(l.quantidade.replace(',', '.')) })),
            p_diagnostico: diagnostico || null, p_sinal_dbm: sinal.trim() ? Number(sinal.replace(',', '.')) : null, p_observacao: obs.trim() || null,
            p_equipamentos: equips.filter((l) => l.itemId && l.serie.trim().length >= 3).map((l) => ({ item_id: l.itemId, numero_serie: l.serie.trim() })),
          }, { onSuccess: aoFechar })}>Confirmar encerramento</Botao>
          <p className="text-xs text-ink-muted">Se faltar material na bolsa o encerramento passa mesmo assim; o saldo fica negativo e o admin repõe.</p>
        </div>
      )}
    </div>
  )
}

export function TecnicoChamadosPage() {
  const chamados = useMeusChamados()
  const [vistoId, setVistoId] = useState<string | null>(null)
  const visto = (chamados.data ?? []).find((o) => o.id === vistoId) ?? null
  const ativos = (chamados.data ?? []).filter((o) => o.status === 'aberto' || o.status === 'em_atendimento' || o.status === 'pausado')
  const encerrados = (chamados.data ?? []).filter((o) => o.status === 'encerrado').slice(0, 10)

  if (chamados.isPending) return <Carregando />
  if (chamados.error != null) return <Alerta tipo="erro">{mensagemDeErro(chamados.error)}</Alerta>

  const CartaoOs = ({ o }: { o: OrdemServico }) => (
    <button type="button" onClick={() => setVistoId(o.id)} className="block w-full rounded-lg border border-line bg-white p-3 text-left text-sm hover:border-brand-600">
      <div className="flex items-center justify-between">
        <span className="font-medium">{ROTULO_TIPO_OS[o.tipo]}{o.prioridade === 'urgente' && <span className="ml-1 text-red-700">!</span>}</span>
        <Distintivo tom={TOM_STATUS[o.status]}>{ROTULO_STATUS_OS[o.status]}</Distintivo>
      </div>
      <p className="mt-1 line-clamp-2 text-ink-muted">{o.descricao}</p>
      <p className="mt-1 text-xs text-ink-muted">{o.numero}{o.data_agendada ? ` · ${formatarData(o.data_agendada)} ${o.hora_agendada?.slice(0, 5)}` : ' · agendar'}</p>
    </button>
  )

  return (
    <div className="space-y-4">
      <h2 className="text-sm font-semibold">Em aberto ({ativos.length})</h2>
      {ativos.length === 0 && <p className="rounded-md border border-line bg-white p-4 text-center text-sm text-ink-muted">Nenhum chamado no momento. 👍</p>}
      <div className="space-y-2">{ativos.map((o) => <CartaoOs key={o.id} o={o} />)}</div>
      {encerrados.length > 0 && (
        <>
          <h2 className="pt-2 text-sm font-semibold text-ink-muted">Encerrados recentes</h2>
          <div className="space-y-2 opacity-70">{encerrados.map((o) => <CartaoOs key={o.id} o={o} />)}</div>
        </>
      )}
      <Modal aberto={visto !== null} aoFechar={() => setVistoId(null)} largura="md" titulo={visto?.numero ?? ''}>
        {visto && <DetalheTecnico key={visto.id + visto.status + String(visto.data_agendada ?? '')} os={visto} aoFechar={() => setVistoId(null)} />}
      </Modal>
    </div>
  )
}
