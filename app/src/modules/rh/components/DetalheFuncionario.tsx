import { useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Carregando } from '../../../core/ui/Carregando'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda, hojeISO } from '../../../core/formatos'
import type { Conta } from '../../contas/tipos'
import type { CentroCusto } from '../../centros_custo/tipos'
import { useAtualizarFerias, useCriarFerias, useFerias, useFolha, useLancarFolha, usePonto, useRegistrarPonto } from '../api'
import { horasTrabalhadas, ROTULO_STATUS_FERIAS, STATUS_FERIAS, type Funcionario, type StatusFerias } from '../tipos'

const TOM_FERIAS: Record<StatusFerias, 'ok' | 'alerta' | 'neutro' | 'info'> = { programada: 'info', em_gozo: 'alerta', concluida: 'ok', cancelada: 'neutro' }

type Aba = 'ponto' | 'ferias' | 'folha'

function AbaPonto({ funcionarioId }: { funcionarioId: string }) {
  const pontos = usePonto(funcionarioId)
  const registrar = useRegistrarPonto()
  const [data, setData] = useState(hojeISO())
  const [entrada, setEntrada] = useState('')
  const [saidaAlmoco, setSaidaAlmoco] = useState('')
  const [voltaAlmoco, setVoltaAlmoco] = useState('')
  const [saida, setSaida] = useState('')

  function registrarHoje() {
    registrar.mutate(
      { funcionario_id: funcionarioId, data, entrada: entrada || null, saida_almoco: saidaAlmoco || null, volta_almoco: voltaAlmoco || null, saida: saida || null, observacao: null },
      { onSuccess: () => { setEntrada(''); setSaidaAlmoco(''); setVoltaAlmoco(''); setSaida('') } },
    )
  }

  return (
    <div className="space-y-4">
      <p className="text-xs text-ink-muted">Ponto informal — controle interno, sem valor jurídico pleno (não substitui um REP-P homologado).</p>
      {registrar.error && <Alerta tipo="erro">{mensagemDeErro(registrar.error)}</Alerta>}
      <div className="grid grid-cols-5 gap-2 items-end">
        <Campo rotulo="Data" type="date" value={data} onChange={(e) => setData(e.target.value)} />
        <Campo rotulo="Entrada" type="time" value={entrada} onChange={(e) => setEntrada(e.target.value)} />
        <Campo rotulo="Saída almoço" type="time" value={saidaAlmoco} onChange={(e) => setSaidaAlmoco(e.target.value)} />
        <Campo rotulo="Volta almoço" type="time" value={voltaAlmoco} onChange={(e) => setVoltaAlmoco(e.target.value)} />
        <Campo rotulo="Saída" type="time" value={saida} onChange={(e) => setSaida(e.target.value)} />
      </div>
      <Botao onClick={registrarHoje} carregando={registrar.isPending}>Registrar</Botao>
      {pontos.isPending && <Carregando texto="Carregando ponto…" />}
      {pontos.isSuccess && (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
              <tr className="border-b border-line"><th className="py-2 pr-3">Data</th><th className="py-2 pr-3">Entrada</th><th className="py-2 pr-3">Almoço</th><th className="py-2 pr-3">Saída</th><th className="py-2 pr-3">Horas</th></tr>
            </thead>
            <tbody>
              {pontos.data.map((p) => (
                <tr key={p.id} className="border-b border-line last:border-0">
                  <td className="py-2 pr-3">{formatarData(p.data)}</td>
                  <td className="py-2 pr-3 tabular-nums">{p.entrada ?? '—'}</td>
                  <td className="py-2 pr-3 tabular-nums">{p.saida_almoco && p.volta_almoco ? `${p.saida_almoco}–${p.volta_almoco}` : '—'}</td>
                  <td className="py-2 pr-3 tabular-nums">{p.saida ?? '—'}</td>
                  <td className="py-2 pr-3 tabular-nums">{horasTrabalhadas(p) ?? '—'}</td>
                </tr>
              ))}
              {pontos.data.length === 0 && <tr><td colSpan={5} className="py-6 text-center text-ink-muted">Nenhum registro ainda.</td></tr>}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function AbaFerias({ funcionarioId }: { funcionarioId: string }) {
  const ferias = useFerias(funcionarioId)
  const criar = useCriarFerias()
  const mover = useAtualizarFerias()
  const [aquisitivoInicio, setAquisitivoInicio] = useState('')
  const [aquisitivoFim, setAquisitivoFim] = useState('')
  const [dataInicio, setDataInicio] = useState('')
  const [dataFim, setDataFim] = useState('')

  function programar() {
    if (!aquisitivoInicio || !aquisitivoFim) return
    criar.mutate(
      { funcionario_id: funcionarioId, periodo_aquisitivo_inicio: aquisitivoInicio, periodo_aquisitivo_fim: aquisitivoFim, data_inicio: dataInicio || null, data_fim: dataFim || null, status: 'programada', observacao: null },
      { onSuccess: () => { setAquisitivoInicio(''); setAquisitivoFim(''); setDataInicio(''); setDataFim('') } },
    )
  }

  return (
    <div className="space-y-4">
      <p className="text-xs text-ink-muted">Tracker de datas — sem cálculo de 1/3 constitucional ou abono pecuniário (isso é folha/contador).</p>
      {criar.error && <Alerta tipo="erro">{mensagemDeErro(criar.error)}</Alerta>}
      <div className="grid grid-cols-4 gap-2 items-end">
        <Campo rotulo="Aquisitivo de" type="date" value={aquisitivoInicio} onChange={(e) => setAquisitivoInicio(e.target.value)} />
        <Campo rotulo="Aquisitivo até" type="date" value={aquisitivoFim} onChange={(e) => setAquisitivoFim(e.target.value)} />
        <Campo rotulo="Gozo início (opcional)" type="date" value={dataInicio} onChange={(e) => setDataInicio(e.target.value)} />
        <Campo rotulo="Gozo fim (opcional)" type="date" value={dataFim} onChange={(e) => setDataFim(e.target.value)} />
      </div>
      <Botao onClick={programar} carregando={criar.isPending} disabled={!aquisitivoInicio || !aquisitivoFim}>Programar férias</Botao>
      {ferias.isPending && <Carregando texto="Carregando férias…" />}
      {ferias.isSuccess && (
        <ul className="divide-y divide-line rounded-md border border-line">
          {ferias.data.map((f) => (
            <li key={f.id} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm">
              <span>Aquisitivo {formatarData(f.periodo_aquisitivo_inicio)}–{formatarData(f.periodo_aquisitivo_fim)}{f.data_inicio ? ` · gozo ${formatarData(f.data_inicio)}${f.data_fim ? `–${formatarData(f.data_fim)}` : ''}` : ''}</span>
              <span className="flex items-center gap-2">
                <Distintivo tom={TOM_FERIAS[f.status]}>{ROTULO_STATUS_FERIAS[f.status]}</Distintivo>
                {f.status !== 'concluida' && f.status !== 'cancelada' && (
                  <Selecao rotulo="" opcoes={STATUS_FERIAS.map((s) => ({ valor: s, rotulo: ROTULO_STATUS_FERIAS[s] }))} value={f.status} onChange={(e) => mover.mutate({ id: f.id, funcionario_id: funcionarioId, status: e.target.value as StatusFerias })} className="h-8" />
                )}
              </span>
            </li>
          ))}
          {ferias.data.length === 0 && <li className="px-3 py-6 text-center text-ink-muted">Nenhuma férias programada ainda.</li>}
        </ul>
      )}
    </div>
  )
}

function AbaFolha({ funcionario, contas, centros }: { funcionario: Funcionario; contas: Conta[]; centros: CentroCusto[] }) {
  const folha = useFolha(funcionario.id)
  const lancar = useLancarFolha()
  const [mes, setMes] = useState(hojeISO().slice(0, 7))
  const [valor, setValor] = useState(String(funcionario.salario_base))
  const [contaId, setContaId] = useState('')
  const [vencimento, setVencimento] = useState(hojeISO())
  const [centroId, setCentroId] = useState('')
  const [observacao, setObservacao] = useState('')
  const centrosDoNegocio = centros.filter((c) => c.negocio_id === funcionario.negocio_id && c.ativo)

  function lancarFolha() {
    const v = Number(valor.replace(',', '.'))
    if (Number.isNaN(v) || v <= 0 || !contaId) return
    lancar.mutate(
      { funcionario_id: funcionario.id, mes: `${mes}-01`, valor: Math.round(v * 100) / 100, conta_id: contaId, vencimento, centro_custo_id: centroId || null, observacao: observacao.trim() || null },
      { onSuccess: () => setObservacao('') },
    )
  }

  return (
    <div className="space-y-4">
      <p className="text-xs text-ink-muted">Um lançamento de despesa por mês — valor final (salário + comissões − descontos) informado manualmente. Sem cálculo de INSS/IRRF/FGTS.</p>
      {lancar.error && <Alerta tipo="erro">{mensagemDeErro(lancar.error)}</Alerta>}
      <div className="grid grid-cols-3 gap-2">
        <Campo rotulo="Mês" type="month" value={mes} onChange={(e) => setMes(e.target.value)} />
        <Campo rotulo="Valor final (R$)" type="number" inputMode="decimal" step="0.01" min="0.01" value={valor} onChange={(e) => setValor(e.target.value)} />
        <Campo rotulo="Vencimento" type="date" value={vencimento} onChange={(e) => setVencimento(e.target.value)} />
      </div>
      <div className="grid grid-cols-2 gap-2">
        <Selecao rotulo="Conta de pagamento" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...contas.filter((c) => c.ativo).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} />
        <Selecao rotulo="Centro de custo (opcional)" opcoes={[{ valor: '', rotulo: 'Geral' }, ...centrosDoNegocio.map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={centroId} onChange={(e) => setCentroId(e.target.value)} />
      </div>
      <Campo rotulo="Observação (opcional)" value={observacao} onChange={(e) => setObservacao(e.target.value)} placeholder="ex.: salário + comissões de setembro" />
      <Botao onClick={lancarFolha} carregando={lancar.isPending} disabled={!contaId}>Lançar folha do mês</Botao>
      {folha.isPending && <Carregando texto="Carregando folha…" />}
      {folha.isSuccess && (
        <ul className="divide-y divide-line rounded-md border border-line">
          {folha.data.map((f) => (
            <li key={f.id} className="flex items-center justify-between px-3 py-2 text-sm">
              <span>{f.mes.slice(5, 7)}/{f.mes.slice(0, 4)}{f.observacao ? ` · ${f.observacao}` : ''}</span>
              <span className="font-medium tabular-nums">{formatarMoeda(f.valor)}</span>
            </li>
          ))}
          {folha.data.length === 0 && <li className="px-3 py-6 text-center text-ink-muted">Nenhuma folha lançada ainda.</li>}
        </ul>
      )}
    </div>
  )
}

export function DetalheFuncionario({ funcionario, contas, centros }: { funcionario: Funcionario; contas: Conta[]; centros: CentroCusto[] }) {
  const [aba, setAba] = useState<Aba>('ponto')
  return (
    <div className="space-y-4">
      <div role="tablist" className="flex gap-1 rounded-md border border-line p-1 text-sm">
        {(['ponto', 'ferias', 'folha'] as Aba[]).map((a) => (
          <button key={a} role="tab" aria-selected={aba === a} onClick={() => setAba(a)} className={`rounded px-3 py-1.5 ${aba === a ? 'bg-brand-600 text-white' : 'text-ink-muted hover:text-ink'}`}>
            {a === 'ponto' ? 'Ponto' : a === 'ferias' ? 'Férias' : 'Folha'}
          </button>
        ))}
      </div>
      {aba === 'ponto' && <AbaPonto funcionarioId={funcionario.id} />}
      {aba === 'ferias' && <AbaFerias funcionarioId={funcionario.id} />}
      {aba === 'folha' && <AbaFolha funcionario={funcionario} contas={contas} centros={centros} />}
    </div>
  )
}
