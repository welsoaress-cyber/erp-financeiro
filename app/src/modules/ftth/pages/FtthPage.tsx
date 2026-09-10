import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { Carregando } from '../../../core/ui/Carregando'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useContratos } from '../../contratos/api'
import { codigoContrato } from '../../contratos/tipos'
import { useClientesMapa, useCtos, useDefeitoPorta, useHistoricoCto, useLiberarPorta, usePortasCto, useRotaCliente, useRotaPop, useSalvarCto, useTrocarPorta, useVincularPorta } from '../api'
import { MapaCtos } from '../components/MapaCtos'
import { buscarEndereco, ocupacaoDe, ROTULO_EVENTO, ROTULO_STATUS_CTO, type ClienteNoMapa, type CtoOcupacao, type CtoPorta, type DadosCto, type StatusCto, type TipoPontoRede } from '../tipos'

type Aba = 'mapa' | 'ctos' | 'historico'

function FormularioCto({ cto, tipoFixo, negocioServnet, ctos, salvando, erro, aoSalvar, aoCancelar }: {
  cto?: CtoOcupacao; tipoFixo?: TipoPontoRede; negocioServnet: string; ctos: CtoOcupacao[]; salvando: boolean; erro: string | null
  aoSalvar: (d: DadosCto & { id?: string }) => void; aoCancelar: () => void
}) {
  const tipo = cto?.tipo ?? tipoFixo ?? 'cto'
  const [popId, setPopId] = useState(cto?.pop_id ?? '')
  const pops = ctos.filter((c) => c.tipo === 'pop')
  const proximo = tipo === 'pop'
    ? `POP-${String(pops.length + 1).padStart(2, '0')}`
    : `CTO-${String(ctos.filter((c) => c.tipo === 'cto').length + 1).padStart(3, '0')}`
  const [codigo, setCodigo] = useState(cto?.codigo ?? proximo)
  const [endereco, setEndereco] = useState(cto?.endereco ?? '')
  const [referencia, setReferencia] = useState(cto?.referencia ?? '')
  const [ponto, setPonto] = useState<[number, number] | null>(cto ? [cto.latitude, cto.longitude] : null)
  const [portas, setPortas] = useState(String(cto?.quantidade_portas ?? 8))
  const [splitter, setSplitter] = useState(cto?.splitter ?? '1x8')
  const [status, setStatus] = useState<StatusCto>(cto?.status ?? 'ativa')
  const [observacao, setObservacao] = useState(cto?.observacao ?? '')
  const [erroForm, setErroForm] = useState<string | null>(null)

  function enviar() {
    const n = Number(portas)
    if (codigo.trim().length < 2) { setErroForm('Informe o código.'); return }
    if (!ponto) { setErroForm('Clique no mapa para marcar a localização da CTO.'); return }
    if (!Number.isInteger(n) || n < 1 || n > 64) { setErroForm('Quantidade de portas entre 1 e 64.'); return }
    setErroForm(null)
    aoSalvar({ id: cto?.id, negocio_id: cto?.negocio_id ?? negocioServnet, codigo: codigo.trim(), endereco: endereco.trim() || null, referencia: referencia.trim() || null, latitude: ponto[0], longitude: ponto[1], quantidade_portas: tipo === 'pop' ? 1 : n, splitter: tipo === 'pop' ? null : splitter || null, status, observacao: observacao.trim() || null, tipo, pop_id: tipo === 'cto' ? popId || null : null })
  }

  return (
    <div className="space-y-4">
      {(erro ?? erroForm) && <Alerta tipo="erro">{erro ?? erroForm}</Alerta>}
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Código" value={codigo} onChange={(e) => setCodigo(e.target.value)} maxLength={20} />
        <Selecao rotulo="Status" opcoes={Object.entries(ROTULO_STATUS_CTO).map(([valor, rotulo]) => ({ valor, rotulo }))} value={status} onChange={(e) => setStatus(e.target.value as StatusCto)} />
      </div>
      <div className="grid grid-cols-2 gap-4">
        {tipo === 'cto' && (
          <Selecao rotulo="Fibra vem do POP" opcoes={[{ valor: '', rotulo: pops.length === 0 ? 'Cadastre o POP primeiro' : 'Sem fio no mapa' }, ...pops.map((p) => ({ valor: p.id, rotulo: p.codigo }))]} value={popId} onChange={(e) => setPopId(e.target.value)} />
        )}
      </div>
      {tipo === 'cto' && (
        <div className="grid grid-cols-2 gap-4">
          <Campo rotulo="Quantidade de portas" type="number" min={1} max={64} value={portas} onChange={(e) => setPortas(e.target.value)} />
          <Selecao rotulo="Splitter" opcoes={['1x2', '1x4', '1x8', '1x16', '1x32', '1x64'].map((s) => ({ valor: s, rotulo: s }))} value={splitter} onChange={(e) => { setSplitter(e.target.value); setPortas(e.target.value.split('x')[1]) }} />
        </div>
      )}
      <Campo rotulo="Endereço (opcional)" value={endereco} onChange={(e) => setEndereco(e.target.value)} maxLength={200} placeholder="Rua, número, bairro" />
      <Campo rotulo="Referência (opcional)" value={referencia} onChange={(e) => setReferencia(e.target.value)} maxLength={120} placeholder="Ex.: poste em frente ao mercado" />
      <div>
        <p className="mb-1 text-sm font-medium text-ink">Localização — clique no mapa para marcar o ponto {ponto && <span className="font-normal text-ink-muted">({ponto[0]}, {ponto[1]})</span>}</p>
        <MapaCtos ctos={ctos} altura="18rem" comBusca aoClicarMapa={(lat, lng) => setPonto([lat, lng])} marcadorSelecao={ponto} />
      </div>
      <Campo rotulo="Observação (opcional)" value={observacao} onChange={(e) => setObservacao(e.target.value)} maxLength={500} />
      <div className="flex justify-end gap-2">
        <Botao variante="secundario" onClick={aoCancelar} disabled={salvando}>Cancelar</Botao>
        <Botao onClick={enviar} carregando={salvando}>{cto ? 'Salvar alterações' : tipo === 'pop' ? 'Criar POP' : 'Criar CTO'}</Botao>
      </div>
    </div>
  )
}

const COR_PORTA = (p: CtoPorta) => p.defeito ? 'border-red-400 bg-red-50 text-red-800' : p.status === 'ocupada' ? 'border-brand-600 bg-brand-50' : p.status === 'reservada' ? 'border-amber-400 bg-amber-50' : p.drop_disponivel ? 'border-green-500 bg-green-50' : 'border-line bg-white'

const COR_FIO = (p: CtoPorta) => p.defeito ? '#dc2626' : p.status === 'ocupada' ? '#1d4ed8' : p.status === 'reservada' ? '#d97706' : p.drop_disponivel ? '#15803d' : '#9ca3af'

/** Esquema interno da CTO: fibra do POP → splitter 1xN → portas. */
function DiagramaSplitter({ cto, pop, portas, nomePessoa }: { cto: CtoOcupacao; pop: CtoOcupacao | null; portas: CtoPorta[]; nomePessoa: Map<string, string> }) {
  const n = portas.length
  if (n === 0) return null
  const alturaLinha = 26
  const h = Math.max(n * alturaLinha + 20, 120)
  const ySplitter = h / 2
  const yPorta = (i: number) => 14 + i * alturaLinha
  return (
    <div className="overflow-x-auto rounded-md border border-line bg-surface/40 p-2">
      <svg width="640" height={h} viewBox={`0 0 640 ${h}`} className="min-w-[640px] text-xs">
        {/* fibra do POP */}
        <line x1="8" y1={ySplitter} x2="150" y2={ySplitter} stroke="#2563eb" strokeWidth="2.5" strokeDasharray="7 4" />
        <text x="12" y={ySplitter - 8} fill="#1d4ed8" fontWeight="600">{pop ? `fibra do ${pop.codigo}` : 'fibra (POP não definido)'}</text>
        {/* splitter */}
        <rect x="150" y={ySplitter - 22} width="86" height="44" rx="6" fill="#eff6ff" stroke="#1d4ed8" strokeWidth="1.5" />
        <text x="193" y={ySplitter - 4} textAnchor="middle" fill="#1d4ed8" fontWeight="700">Splitter</text>
        <text x="193" y={ySplitter + 12} textAnchor="middle" fill="#1d4ed8">{cto.splitter ?? `1x${n}`}</text>
        {/* saídas para as portas */}
        {portas.map((p, i) => {
          const y = yPorta(i)
          const cor = COR_FIO(p)
          const rotulo = p.defeito ? 'defeito' : p.status === 'ocupada' ? (p.pessoa_id ? nomePessoa.get(p.pessoa_id) ?? 'ocupada' : 'ocupada') : p.status === 'reservada' ? `reservada${p.pessoa_id ? ` · ${nomePessoa.get(p.pessoa_id) ?? ''}` : ''}` : p.drop_disponivel ? 'livre · drop disponível' : 'livre'
          return (
            <g key={p.id}>
              <path d={`M 236 ${ySplitter} C 280 ${ySplitter}, 280 ${y}, 320 ${y}`} fill="none" stroke={cor} strokeWidth="1.8" opacity={p.status === 'livre' && !p.drop_disponivel && !p.defeito ? 0.45 : 0.95} />
              <circle cx="326" cy={y} r="4" fill={cor} />
              <text x="336" y={y + 4} fill="#374151"><tspan fontWeight="700">P{p.numero}</tspan> · {rotulo}</text>
            </g>
          )
        })}
      </svg>
    </div>
  )
}

function DetalheCto({ cto, aoEditar }: { cto: CtoOcupacao; aoEditar: () => void }) {
  const portas = usePortasCto(cto.id)
  const historico = useHistoricoCto(cto.id)
  const pessoas = usePessoas()
  const contratos = useContratos()
  const ctos = useCtos()
  const vincular = useVincularPorta(); const liberar = useLiberarPorta(); const trocar = useTrocarPorta(); const defeito = useDefeitoPorta()
  const rotaCliente = useRotaCliente(); const rotaPop = useRotaPop()
  const [porta, setPorta] = useState<CtoPorta | null>(null)
  const [marcandoLocal, setMarcandoLocal] = useState(false)
  const [pontosCliente, setPontosCliente] = useState<[number, number][]>([])
  const [desenhandoPop, setDesenhandoPop] = useState(false)
  const [pontosPop, setPontosPop] = useState<[number, number][]>([])
  const [pessoaId, setPessoaId] = useState(''); const [contratoId, setContratoId] = useState(''); const [reservar, setReservar] = useState(false)
  const [destinoCto, setDestinoCto] = useState(cto.id); const [destinoPorta, setDestinoPorta] = useState('')
  const portasDestino = usePortasCto(destinoCto)
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const contratosDoCliente = (contratos.data ?? []).filter((c) => c.pessoa_id === pessoaId && c.negocio_id === cto.negocio_id && c.status === 'ativo')
  const clientesComContrato = useMemo(() => {
    const comContrato = new Set((contratos.data ?? []).filter((c) => c.negocio_id === cto.negocio_id && c.status === 'ativo').map((c) => c.pessoa_id))
    return (pessoas.data ?? []).filter((p) => comContrato.has(p.id))
  }, [contratos.data, pessoas.data, cto.negocio_id])
  const erro = vincular.error ?? liberar.error ?? trocar.error ?? defeito.error ?? rotaCliente.error ?? rotaPop.error
  const ocupado = vincular.isPending || liberar.isPending || trocar.isPending || defeito.isPending || rotaCliente.isPending || rotaPop.isPending
  const pop = (ctos.data ?? []).find((c) => c.id === cto.pop_id) ?? null
  const { pct, tom } = ocupacaoDe(cto)

  function fecharPorta() { setPorta(null); setMarcandoLocal(false); setPontosCliente([]); setPessoaId(''); setContratoId(''); setReservar(false); setDestinoPorta(''); setDestinoCto(cto.id); vincular.reset(); liberar.reset(); trocar.reset(); defeito.reset(); rotaCliente.reset(); rotaPop.reset() }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3 text-sm">
        <Distintivo tom={cto.status === 'ativa' ? 'ok' : 'neutro'}>{ROTULO_STATUS_CTO[cto.status]}</Distintivo>
        <span className={tom === 'lotada' ? 'font-semibold text-red-700' : tom === 'quase' ? 'font-semibold text-amber-700' : ''}>{pct}% ocupada ({cto.ocupadas + cto.reservadas}/{cto.quantidade_portas})</span>
        {cto.com_defeito > 0 && <span className="text-red-700">{cto.com_defeito} porta(s) com defeito</span>}
        {cto.drops_disponiveis > 0 && <span className="text-green-700">{cto.drops_disponiveis} drop(s) disponível(is)</span>}
        <span className="text-ink-muted">{cto.endereco ?? ''}{cto.referencia ? ` · ${cto.referencia}` : ''}</span>
        <Botao variante="secundario" onClick={aoEditar}>{cto.tipo === 'pop' ? 'Editar POP' : 'Editar CTO'}</Botao>
      </div>
      {tom !== 'ok' && <Alerta tipo={tom === 'lotada' ? 'erro' : 'info'} titulo={tom === 'lotada' ? 'CTO lotada' : 'CTO quase lotada (≥90%)'}>Planeje uma nova CTO ou libere portas nesta região.</Alerta>}
      {erro != null && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}

      {cto.tipo === 'cto' && pop && (
        <div className="space-y-2">
          <Botao variante="secundario" onClick={() => { setDesenhandoPop((v) => !v); setPontosPop([]) }}>{desenhandoPop ? 'Cancelar desenho do fio do POP' : cto.rota_pop ? `Redesenhar fio ${pop.codigo} → ${cto.codigo}` : `Desenhar fio ${pop.codigo} → ${cto.codigo}`}</Botao>
          {desenhandoPop && (
            <>
              <p className="text-xs text-ink-muted">Clique no mapa seguindo o caminho do cabo a partir do POP; a chegada na CTO é ligada automaticamente. Salvar sem pontos = linha reta.</p>
              <MapaCtos
                ctos={[pop, cto]}
                altura="18rem"
                comBusca
                desenho={{ ancora: [pop.latitude, pop.longitude], pontos: pontosPop }}
                aoClicarMapa={(lat, lng) => setPontosPop((xs) => [...xs, [lat, lng]])}
              />
              <div className="flex gap-2">
                <Botao carregando={ocupado} onClick={() => rotaPop.mutate({ cto_id: cto.id, rota: pontosPop }, { onSuccess: () => { setDesenhandoPop(false); setPontosPop([]) } })}>Salvar fio ({pontosPop.length} vértice(s))</Botao>
                <Botao variante="secundario" disabled={pontosPop.length === 0} onClick={() => setPontosPop((xs) => xs.slice(0, -1))}>Desfazer último</Botao>
                <Botao variante="secundario" disabled={pontosPop.length === 0} onClick={() => setPontosPop([])}>Limpar</Botao>
              </div>
            </>
          )}
        </div>
      )}

      {cto.tipo === 'cto' && !portas.isPending && (
        <DiagramaSplitter cto={cto} pop={pop} portas={portas.data ?? []} nomePessoa={nomePessoa} />
      )}
      {cto.tipo === 'pop' ? <p className="text-sm text-ink-muted">POP (central do provedor): sem portas de cliente. Os fios até as CTOs são desenhados no detalhe de cada CTO.</p> : portas.isPending ? <Carregando /> : (
        <div className="grid grid-cols-4 gap-2 sm:grid-cols-8">
          {(portas.data ?? []).map((p) => (
            <button key={p.id} type="button" onClick={() => { fecharPorta(); setPorta(p) }} className={`rounded-md border p-2 text-center text-xs ${COR_PORTA(p)} ${porta?.id === p.id ? 'ring-2 ring-brand-600' : ''}`}>
              <span className="block text-sm font-semibold">{p.numero}</span>
              {p.defeito ? 'defeito' : p.status === 'livre' ? (p.drop_disponivel ? 'drop livre' : 'livre') : p.status === 'reservada' ? 'reservada' : 'ocupada'}
              {p.pessoa_id && <span className="block truncate" title={nomePessoa.get(p.pessoa_id)}>{nomePessoa.get(p.pessoa_id)}</span>}
            </button>
          ))}
        </div>
      )}

      {porta && (
        <div className="space-y-3 rounded-md border border-line bg-surface/60 p-3">
          <p className="text-sm font-medium">Porta {porta.numero} · {porta.defeito ? 'com defeito' : porta.status}{porta.drop_disponivel && porta.status === 'livre' && ' · drop disponível para utilização'}{porta.pessoa_id && ` · ${nomePessoa.get(porta.pessoa_id) ?? ''}`}{porta.data_ocupacao && ` · desde ${formatarData(porta.data_ocupacao)}`}</p>
          {porta.status === 'livre' && !porta.defeito && (
            <div className="grid gap-3 sm:grid-cols-3">
              <Selecao rotulo="Cliente (com contrato ativo)" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...clientesComContrato.map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={pessoaId} onChange={(e) => { setPessoaId(e.target.value); setContratoId('') }} />
              <Selecao rotulo="Contrato" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...contratosDoCliente.map((c) => ({ valor: c.id, rotulo: `${codigoContrato(c)} · venc. dia ${c.dia_vencimento}` }))]} value={contratoId} onChange={(e) => setContratoId(e.target.value)} />
              <div className="flex items-end gap-2 pb-0.5">
                <label className="flex items-center gap-1.5 text-sm"><input type="checkbox" checked={reservar} onChange={(e) => setReservar(e.target.checked)} className="size-4 accent-brand-600" />Reservar</label>
                <Botao carregando={ocupado} disabled={!pessoaId || !contratoId} onClick={() => vincular.mutate({ porta_id: porta.id, pessoa_id: pessoaId, contrato_id: contratoId, reservar }, { onSuccess: (pt) => {
                  // endereço no cadastro → geocodifica e desenha o fio sozinho (reta CTO→casa; refine depois com vértices)
                  const end = (pessoas.data ?? []).find((x) => x.id === pessoaId)?.endereco
                  if (end) void buscarEndereco(end).then((r) => { if (r) rotaCliente.mutate({ porta_id: pt.id, rota: [[r.lat, r.lng]] }) }).catch(() => null)
                  fecharPorta()
                } })}>{reservar ? 'Reservar' : 'Vincular'}</Botao>
              </div>
            </div>
          )}
          {porta.status !== 'livre' && (
            <div className="flex flex-wrap items-end gap-3">
              {porta.status === 'reservada' && porta.pessoa_id && porta.contrato_id && (
                <Botao carregando={ocupado} onClick={() => vincular.mutate({ porta_id: porta.id, pessoa_id: porta.pessoa_id!, contrato_id: porta.contrato_id! }, { onSuccess: fecharPorta })}>Efetivar instalação</Botao>
              )}
              <Botao variante="secundario" carregando={ocupado} onClick={() => liberar.mutate({ porta_id: porta.id }, { onSuccess: fecharPorta })}>Liberar porta</Botao>
              <div className="flex items-end gap-2">
                <Selecao rotulo="Trocar para CTO" opcoes={(ctos.data ?? []).filter((c) => c.negocio_id === cto.negocio_id && c.status === 'ativa').map((c) => ({ valor: c.id, rotulo: c.codigo }))} value={destinoCto} onChange={(e) => { setDestinoCto(e.target.value); setDestinoPorta('') }} />
                <Selecao rotulo="Porta" opcoes={[{ valor: '', rotulo: '…' }, ...(portasDestino.data ?? []).filter((p) => p.status === 'livre' && !p.defeito && p.id !== porta.id).map((p) => ({ valor: p.id, rotulo: `${p.numero}${p.drop_disponivel ? ' (drop)' : ''}` }))]} value={destinoPorta} onChange={(e) => setDestinoPorta(e.target.value)} />
                <Botao variante="secundario" carregando={ocupado} disabled={!destinoPorta} onClick={() => trocar.mutate({ origem_id: porta.id, destino_id: destinoPorta }, { onSuccess: fecharPorta })}>Trocar</Botao>
              </div>
            </div>
          )}
          <div className="flex flex-wrap gap-2">
            <Botao variante={porta.defeito ? 'secundario' : 'perigo'} carregando={ocupado} onClick={() => defeito.mutate({ porta_id: porta.id, defeito: !porta.defeito }, { onSuccess: fecharPorta })}>{porta.defeito ? 'Marcar reparada' : 'Marcar defeito'}</Botao>
            {porta.status !== 'livre' && (
              <Botao variante="secundario" onClick={() => { setMarcandoLocal((v) => !v); setPontosCliente([]) }}>{marcandoLocal ? 'Cancelar desenho' : porta.rota_cliente ? 'Redesenhar fio até o cliente' : 'Desenhar fio até o cliente'}</Botao>
            )}
          </div>
          {marcandoLocal && (
            <div className="space-y-2">
              <p className="text-xs text-ink-muted">Clique no mapa seguindo o caminho do cabo (postes/esquinas): cada clique é um vértice. O <b>último ponto é a casa do cliente</b>. Depois clique em Salvar fio.</p>
              <MapaCtos
                ctos={[cto]}
                altura="18rem"
                comBusca
                buscaInicial={porta.pessoa_id ? ((pessoas.data ?? []).find((x) => x.id === porta.pessoa_id)?.endereco ?? null) : null}
                desenho={{ ancora: [cto.latitude, cto.longitude], pontos: pontosCliente }}
                aoClicarMapa={(lat, lng) => setPontosCliente((xs) => [...xs, [lat, lng]])}
              />
              <div className="flex gap-2">
                <Botao carregando={ocupado} disabled={pontosCliente.length === 0} onClick={() => rotaCliente.mutate({ porta_id: porta.id, rota: pontosCliente }, { onSuccess: () => { setMarcandoLocal(false); setPontosCliente([]) } })}>Salvar fio ({pontosCliente.length} ponto(s))</Botao>
                <Botao variante="secundario" disabled={pontosCliente.length === 0} onClick={() => setPontosCliente((xs) => xs.slice(0, -1))}>Desfazer último</Botao>
                <Botao variante="secundario" disabled={pontosCliente.length === 0} onClick={() => setPontosCliente([])}>Limpar</Botao>
              </div>
            </div>
          )}
        </div>
      )}

      <div>
        <p className="mb-1 text-sm font-medium">Histórico deste ponto</p>
        {(historico.data ?? []).length === 0 ? <p className="text-sm text-ink-muted">Sem movimentações.</p> : (
          <ul className="max-h-48 divide-y divide-line overflow-y-auto rounded-md border border-line text-sm">
            {(historico.data ?? []).map((h) => (
              <li key={h.id} className="flex flex-wrap justify-between gap-2 px-3 py-1.5">
                <span>{ROTULO_EVENTO[h.evento]}{h.pessoa_id && ` · ${nomePessoa.get(h.pessoa_id) ?? ''}`}{h.observacao && <span className="text-ink-muted"> · {h.observacao}</span>}</span>
                <span className="text-ink-muted">{new Date(h.criado_em).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}</span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}

export function FtthPage() {
  const negocios = useNegocios()
  const ctos = useCtos()
  const pessoas = usePessoas()
  const salvar = useSalvarCto()
  const [aba, setAba] = useState<Aba>('mapa')
  const [detalhe, setDetalhe] = useState<CtoOcupacao | null>(null)
  const [editando, setEditando] = useState<CtoOcupacao | 'nova' | 'novo-pop' | null>(null)
  const historicoGeral = useHistoricoCto(null)
  const clientesPortas = useClientesMapa()
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const clientesMapa: ClienteNoMapa[] = useMemo(() => {
    const ctoPorId = new Map((ctos.data ?? []).map((c) => [c.id, c]))
    return (clientesPortas.data ?? []).flatMap((p) => {
      const c = ctoPorId.get(p.cto_id)
      if (!c || p.cliente_latitude == null || p.cliente_longitude == null) return []
      return [{ lat: p.cliente_latitude, lng: p.cliente_longitude, nome: (p.pessoa_id ? nomePessoa.get(p.pessoa_id) : null) ?? '—', ctoLat: c.latitude, ctoLng: c.longitude, porta: p.numero, rota: p.rota_cliente }]
    })
  }, [clientesPortas.data, ctos.data, nomePessoa])
  const nomeCto = useMemo(() => new Map((ctos.data ?? []).map((c) => [c.id, c.codigo])), [ctos.data])
  const servnet = (negocios.data ?? []).find((n) => n.nome.toLowerCase().includes('servnet')) ?? (negocios.data ?? [])[0]
  const criticas = (ctos.data ?? []).filter((c) => c.status === 'ativa' && ocupacaoDe(c).tom !== 'ok')

  const detalheAtual = detalhe ? (ctos.data ?? []).find((c) => c.id === detalhe.id) ?? detalhe : null

  return (
    <>
      <CabecalhoPagina titulo="Rede FTTH" descricao="CTOs, portas ópticas e vínculo de clientes"
        acoes={<span className="flex gap-2"><Botao onClick={() => setEditando('novo-pop')}>Novo POP</Botao><Botao onClick={() => setEditando('nova')}>Nova CTO</Botao></span>} />

      {criticas.length > 0 && (
        <div className="mb-4"><Alerta tipo="erro" titulo={`${criticas.length} CTO(s) lotada(s) ou ≥90%`}>
          {criticas.map((c) => `${c.codigo} (${ocupacaoDe(c).pct}%)`).join(' · ')}
        </Alerta></div>
      )}

      <div role="tablist" className="mb-4 flex gap-1 rounded-md border border-line p-1 text-sm">
        {(['mapa', 'ctos', 'historico'] as Aba[]).map((a) => (
          <button key={a} role="tab" aria-selected={aba === a} onClick={() => setAba(a)} className={`rounded px-3 py-1.5 ${aba === a ? 'bg-brand-600 text-white' : 'text-ink-muted hover:text-ink'}`}>
            {a === 'mapa' ? 'Mapa' : a === 'ctos' ? 'CTOs' : 'Histórico'}
          </button>
        ))}
      </div>

      {ctos.isPending && <Carregando />}

      {aba === 'mapa' && ctos.isSuccess && (
        <Cartao className="p-4">
          <MapaCtos ctos={ctos.data} clientes={clientesMapa} comBusca aoClicarCto={(c) => setDetalhe(c)} />
          <p className="mt-2 text-xs text-ink-muted">Azul grande: POP (fio tracejado até as CTOs) · Verde: disponível · Amarelo: ≥90% · Vermelho: lotada · Cinza: inativa · Pontos verdes-água: clientes marcados (fio até a CTO). Clique no pino para abrir.</p>
        </Cartao>
      )}

      {aba === 'ctos' && ctos.isSuccess && (
        <Cartao className="p-0">
          {ctos.data.length === 0 ? <p className="px-6 py-12 text-center text-sm text-ink-muted">Nenhuma CTO cadastrada. Clique em "Nova CTO".</p> : (
            <div className="overflow-x-auto"><table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Código</th><th className="px-4 py-2 font-medium">Endereço</th><th className="px-4 py-2 font-medium">Splitter</th><th className="px-4 py-2 text-right font-medium">Ocupação</th><th className="px-4 py-2 font-medium">Drops</th><th className="px-4 py-2 font-medium">Status</th></tr></thead>
              <tbody>
                {ctos.data.map((c) => { const { pct, tom } = ocupacaoDe(c); return (
                  <tr key={c.id} onClick={() => setDetalhe(c)} className="cursor-pointer border-b border-line last:border-0 hover:bg-surface">
                    <td className="px-4 py-2 font-medium">{c.codigo}{c.com_defeito > 0 && <span className="ml-2 text-xs text-red-700">⚠ {c.com_defeito} defeito(s)</span>}</td>
                    <td className="px-4 py-2 text-ink-muted">{c.endereco ?? '—'}</td>
                    <td className="px-4 py-2 text-ink-muted">{c.splitter ?? '—'}</td>
                    <td className={`px-4 py-2 text-right tabular-nums ${tom === 'lotada' ? 'font-semibold text-red-700' : tom === 'quase' ? 'font-semibold text-amber-700' : ''}`}>{c.ocupadas + c.reservadas}/{c.quantidade_portas} ({pct}%)</td>
                    <td className="px-4 py-2">{c.drops_disponiveis > 0 ? <span className="text-green-700">{c.drops_disponiveis} disponível(is)</span> : '—'}</td>
                    <td className="px-4 py-2"><Distintivo tom={c.status === 'ativa' ? 'ok' : 'neutro'}>{ROTULO_STATUS_CTO[c.status]}</Distintivo></td>
                  </tr>
                ) })}
              </tbody>
            </table></div>
          )}
        </Cartao>
      )}

      {aba === 'historico' && (
        <Cartao className="p-0">
          {(historicoGeral.data ?? []).length === 0 ? <p className="px-6 py-12 text-center text-sm text-ink-muted">Sem movimentações ainda.</p> : (
            <ul className="divide-y divide-line text-sm">
              {(historicoGeral.data ?? []).map((h) => (
                <li key={h.id} className="flex flex-wrap justify-between gap-2 px-4 py-2">
                  <span><span className="font-medium">{nomeCto.get(h.cto_id) ?? '—'}</span> · {ROTULO_EVENTO[h.evento]}{h.pessoa_id && ` · ${nomePessoa.get(h.pessoa_id) ?? ''}`}{h.observacao && <span className="text-ink-muted"> · {h.observacao}</span>}</span>
                  <span className="text-ink-muted">{new Date(h.criado_em).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' })}</span>
                </li>
              ))}
            </ul>
          )}
        </Cartao>
      )}

      <Modal aberto={detalheAtual !== null} aoFechar={() => setDetalhe(null)} largura="xl" titulo={detalheAtual ? `${detalheAtual.codigo}` : ''}>
        {detalheAtual && <DetalheCto cto={detalheAtual} aoEditar={() => { setEditando(detalheAtual); setDetalhe(null) }} />}
      </Modal>

      <Modal aberto={editando !== null} aoFechar={() => { setEditando(null); salvar.reset() }} largura="lg" titulo={editando === 'nova' ? 'Nova CTO' : editando === 'novo-pop' ? 'Novo POP (central do provedor)' : (editando as CtoOcupacao)?.tipo === 'pop' ? 'Editar POP' : 'Editar CTO'}>
        {editando !== null && servnet && (
          <FormularioCto
            key={typeof editando === 'string' ? editando : editando.id}
            cto={typeof editando === 'string' ? undefined : editando}
            tipoFixo={editando === 'novo-pop' ? 'pop' : editando === 'nova' ? 'cto' : undefined}
            negocioServnet={servnet.id}
            ctos={ctos.data ?? []}
            salvando={salvar.isPending}
            erro={salvar.error ? mensagemDeErro(salvar.error) : null}
            aoSalvar={(d) => salvar.mutate(d, { onSuccess: () => { setEditando(null); salvar.reset() } })}
            aoCancelar={() => { setEditando(null); salvar.reset() }}
          />
        )}
      </Modal>
    </>
  )
}
