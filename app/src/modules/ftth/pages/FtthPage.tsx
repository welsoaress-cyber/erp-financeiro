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
import { useCtos, useDefeitoPorta, useHistoricoCto, useLiberarPorta, usePortasCto, useSalvarCto, useTrocarPorta, useVincularPorta } from '../api'
import { MapaCtos } from '../components/MapaCtos'
import { ocupacaoDe, ROTULO_EVENTO, ROTULO_STATUS_CTO, type CtoOcupacao, type CtoPorta, type DadosCto, type StatusCto } from '../tipos'

type Aba = 'mapa' | 'ctos' | 'historico'

function FormularioCto({ cto, negocioServnet, ctos, salvando, erro, aoSalvar, aoCancelar }: {
  cto?: CtoOcupacao; negocioServnet: string; ctos: CtoOcupacao[]; salvando: boolean; erro: string | null
  aoSalvar: (d: DadosCto & { id?: string }) => void; aoCancelar: () => void
}) {
  const proximo = `CTO-${String(ctos.length + 1).padStart(3, '0')}`
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
    aoSalvar({ id: cto?.id, negocio_id: cto?.negocio_id ?? negocioServnet, codigo: codigo.trim(), endereco: endereco.trim() || null, referencia: referencia.trim() || null, latitude: ponto[0], longitude: ponto[1], quantidade_portas: n, splitter: splitter || null, status, observacao: observacao.trim() || null })
  }

  return (
    <div className="space-y-4">
      {(erro ?? erroForm) && <Alerta tipo="erro">{erro ?? erroForm}</Alerta>}
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Código" value={codigo} onChange={(e) => setCodigo(e.target.value)} maxLength={20} />
        <Selecao rotulo="Status" opcoes={Object.entries(ROTULO_STATUS_CTO).map(([valor, rotulo]) => ({ valor, rotulo }))} value={status} onChange={(e) => setStatus(e.target.value as StatusCto)} />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Quantidade de portas" type="number" min={1} max={64} value={portas} onChange={(e) => setPortas(e.target.value)} />
        <Selecao rotulo="Splitter" opcoes={['1x2', '1x4', '1x8', '1x16', '1x32', '1x64'].map((s) => ({ valor: s, rotulo: s }))} value={splitter} onChange={(e) => { setSplitter(e.target.value); setPortas(e.target.value.split('x')[1]) }} />
      </div>
      <Campo rotulo="Endereço (opcional)" value={endereco} onChange={(e) => setEndereco(e.target.value)} maxLength={200} placeholder="Rua, número, bairro" />
      <Campo rotulo="Referência (opcional)" value={referencia} onChange={(e) => setReferencia(e.target.value)} maxLength={120} placeholder="Ex.: poste em frente ao mercado" />
      <div>
        <p className="mb-1 text-sm font-medium text-ink">Localização — clique no mapa para marcar o ponto {ponto && <span className="font-normal text-ink-muted">({ponto[0]}, {ponto[1]})</span>}</p>
        <MapaCtos ctos={ctos} altura="18rem" aoClicarMapa={(lat, lng) => setPonto([lat, lng])} marcadorSelecao={ponto} />
      </div>
      <Campo rotulo="Observação (opcional)" value={observacao} onChange={(e) => setObservacao(e.target.value)} maxLength={500} />
      <div className="flex justify-end gap-2">
        <Botao variante="secundario" onClick={aoCancelar} disabled={salvando}>Cancelar</Botao>
        <Botao onClick={enviar} carregando={salvando}>{cto ? 'Salvar alterações' : 'Criar CTO'}</Botao>
      </div>
    </div>
  )
}

const COR_PORTA = (p: CtoPorta) => p.defeito ? 'border-red-400 bg-red-50 text-red-800' : p.status === 'ocupada' ? 'border-brand-600 bg-brand-50' : p.status === 'reservada' ? 'border-amber-400 bg-amber-50' : p.drop_disponivel ? 'border-green-500 bg-green-50' : 'border-line bg-white'

function DetalheCto({ cto, aoEditar }: { cto: CtoOcupacao; aoEditar: () => void }) {
  const portas = usePortasCto(cto.id)
  const historico = useHistoricoCto(cto.id)
  const pessoas = usePessoas()
  const contratos = useContratos()
  const ctos = useCtos()
  const vincular = useVincularPorta(); const liberar = useLiberarPorta(); const trocar = useTrocarPorta(); const defeito = useDefeitoPorta()
  const [porta, setPorta] = useState<CtoPorta | null>(null)
  const [pessoaId, setPessoaId] = useState(''); const [contratoId, setContratoId] = useState(''); const [reservar, setReservar] = useState(false)
  const [destinoCto, setDestinoCto] = useState(cto.id); const [destinoPorta, setDestinoPorta] = useState('')
  const portasDestino = usePortasCto(destinoCto)
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const contratosDoCliente = (contratos.data ?? []).filter((c) => c.pessoa_id === pessoaId && c.negocio_id === cto.negocio_id && c.status === 'ativo')
  const clientesComContrato = useMemo(() => {
    const comContrato = new Set((contratos.data ?? []).filter((c) => c.negocio_id === cto.negocio_id && c.status === 'ativo').map((c) => c.pessoa_id))
    return (pessoas.data ?? []).filter((p) => comContrato.has(p.id))
  }, [contratos.data, pessoas.data, cto.negocio_id])
  const erro = vincular.error ?? liberar.error ?? trocar.error ?? defeito.error
  const ocupado = vincular.isPending || liberar.isPending || trocar.isPending || defeito.isPending
  const { pct, tom } = ocupacaoDe(cto)

  function fecharPorta() { setPorta(null); setPessoaId(''); setContratoId(''); setReservar(false); setDestinoPorta(''); setDestinoCto(cto.id); vincular.reset(); liberar.reset(); trocar.reset(); defeito.reset() }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3 text-sm">
        <Distintivo tom={cto.status === 'ativa' ? 'ok' : 'neutro'}>{ROTULO_STATUS_CTO[cto.status]}</Distintivo>
        <span className={tom === 'lotada' ? 'font-semibold text-red-700' : tom === 'quase' ? 'font-semibold text-amber-700' : ''}>{pct}% ocupada ({cto.ocupadas + cto.reservadas}/{cto.quantidade_portas})</span>
        {cto.com_defeito > 0 && <span className="text-red-700">{cto.com_defeito} porta(s) com defeito</span>}
        {cto.drops_disponiveis > 0 && <span className="text-green-700">{cto.drops_disponiveis} drop(s) disponível(is)</span>}
        <span className="text-ink-muted">{cto.endereco ?? ''}{cto.referencia ? ` · ${cto.referencia}` : ''}</span>
        <Botao variante="secundario" onClick={aoEditar}>Editar CTO</Botao>
      </div>
      {tom !== 'ok' && <Alerta tipo={tom === 'lotada' ? 'erro' : 'info'} titulo={tom === 'lotada' ? 'CTO lotada' : 'CTO quase lotada (≥90%)'}>Planeje uma nova CTO ou libere portas nesta região.</Alerta>}
      {erro != null && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}

      {portas.isPending ? <Carregando /> : (
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
                <Botao carregando={ocupado} disabled={!pessoaId || !contratoId} onClick={() => vincular.mutate({ porta_id: porta.id, pessoa_id: pessoaId, contrato_id: contratoId, reservar }, { onSuccess: fecharPorta })}>{reservar ? 'Reservar' : 'Vincular'}</Botao>
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
          <div>
            <Botao variante={porta.defeito ? 'secundario' : 'perigo'} carregando={ocupado} onClick={() => defeito.mutate({ porta_id: porta.id, defeito: !porta.defeito }, { onSuccess: fecharPorta })}>{porta.defeito ? 'Marcar reparada' : 'Marcar defeito'}</Botao>
          </div>
        </div>
      )}

      <div>
        <p className="mb-1 text-sm font-medium">Histórico desta CTO</p>
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
  const [editando, setEditando] = useState<CtoOcupacao | 'nova' | null>(null)
  const historicoGeral = useHistoricoCto(null)
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const nomeCto = useMemo(() => new Map((ctos.data ?? []).map((c) => [c.id, c.codigo])), [ctos.data])
  const servnet = (negocios.data ?? []).find((n) => n.nome.toLowerCase().includes('servnet')) ?? (negocios.data ?? [])[0]
  const criticas = (ctos.data ?? []).filter((c) => c.status === 'ativa' && ocupacaoDe(c).tom !== 'ok')

  const detalheAtual = detalhe ? (ctos.data ?? []).find((c) => c.id === detalhe.id) ?? detalhe : null

  return (
    <>
      <CabecalhoPagina titulo="Rede FTTH" descricao="CTOs, portas ópticas e vínculo de clientes"
        acoes={<Botao onClick={() => setEditando('nova')}>Nova CTO</Botao>} />

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
          <MapaCtos ctos={ctos.data} aoClicarCto={(c) => setDetalhe(c)} />
          <p className="mt-2 text-xs text-ink-muted">Verde: disponível · Amarelo: ≥90% · Vermelho: lotada · Cinza: inativa/manutenção. Clique no pino para abrir a CTO.</p>
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

      <Modal aberto={editando !== null} aoFechar={() => { setEditando(null); salvar.reset() }} largura="lg" titulo={editando === 'nova' ? 'Nova CTO' : 'Editar CTO'}>
        {editando !== null && servnet && (
          <FormularioCto
            cto={editando === 'nova' ? undefined : editando}
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
