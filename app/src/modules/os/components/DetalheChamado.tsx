import { useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda, hojeISO } from '../../../core/formatos'
import { useContas } from '../../contas/api'
import { useEstoqueItens } from '../../estoque/api'
import { fmtQtd } from '../../estoque/tipos'
import {
  useAbrirOs, useAgendarOs, useAprovarComissao, useAtualizarOs, useAvaliarOs, useCancelarOs, useCienciaOs,
  useEncerrarOs, useIniciarOs, useOsHistorico, useOsMateriais, usePausarOs, useResponderRemarcacao, useRetomarOs,
  useSolicitarRemarcacao, useTecnicos,
} from '../api'
import { fmtMinutos, ROTULO_DIAGNOSTICO, ROTULO_EVENTO_OS, ROTULO_STATUS_OS, ROTULO_TIPO_OS, type OrdemServico } from '../tipos'

const TOM_STATUS = { aberto: 'info', em_atendimento: 'ok', pausado: 'alerta', encerrado: 'neutro', cancelado: 'neutro' } as const

interface Props {
  os: OrdemServico
  nomes: { pessoa: string | null; tecnico: string | null; cto: string | null; contrato: string | null; item: Map<string, string> }
  aoFechar: () => void
}

/** Detalhe e ações do chamado (visão do admin). */
export function DetalheChamado({ os, nomes, aoFechar }: Props) {
  const materiais = useOsMateriais(os.id)
  const historico = useOsHistorico(os.id)
  const tecnicos = useTecnicos()
  const contas = useContas()
  const itens = useEstoqueItens()
  const ciencia = useCienciaOs(); const agendar = useAgendarOs(); const iniciar = useIniciarOs()
  const pausar = usePausarOs(); const retomar = useRetomarOs(); const encerrar = useEncerrarOs()
  const cancelar = useCancelarOs(); const avaliar = useAvaliarOs(); const comissao = useAprovarComissao()
  const remarcar = useSolicitarRemarcacao(); const responder = useResponderRemarcacao()
  const atualizar = useAtualizarOs(); const reabrir = useAbrirOs()

  const [painel, setPainel] = useState<'nenhum' | 'agendar' | 'remarcar' | 'pausar' | 'encerrar' | 'cancelar' | 'avaliar' | 'comissao'>('nenhum')
  const [data, setData] = useState(hojeISO()); const [hora, setHora] = useState('08:00'); const [motivo, setMotivo] = useState('')
  const [linhas, setLinhas] = useState<{ itemId: string; quantidade: string }[]>([])
  const [diagnostico, setDiagnostico] = useState(''); const [sinal, setSinal] = useState(''); const [obsFim, setObsFim] = useState('')
  const [nota, setNota] = useState('5'); const [resolvido, setResolvido] = useState('sim')
  const [contaId, setContaId] = useState(''); const [venc, setVenc] = useState(hojeISO()); const [valorCom, setValorCom] = useState('')
  const [tecnicoNovo, setTecnicoNovo] = useState('')

  const ocupado = [ciencia, agendar, iniciar, pausar, retomar, encerrar, cancelar, avaliar, comissao, remarcar, responder, atualizar, reabrir].some((m) => m.isPending)
  const erro = [ciencia, agendar, iniciar, pausar, retomar, encerrar, cancelar, avaliar, comissao, remarcar, responder, atualizar, reabrir].map((m) => m.error).find((e) => e != null)
  const aberto = os.status === 'aberto'; const atendendo = os.status === 'em_atendimento'; const pausado = os.status === 'pausado'; const encerrado = os.status === 'encerrado'
  const itensNegocio = (itens.data ?? []).filter((i) => i.negocio_id === os.negocio_id && i.ativo)
  const fechar = { onSuccess: () => setPainel('nenhum') }

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-3 text-sm">
        <div>
          <p className="font-mono text-xs text-ink-muted">{os.numero}{os.retorno && <Distintivo tom="alerta">Retorno ≤ 7 dias</Distintivo>}</p>
          <p className="font-medium">{ROTULO_TIPO_OS[os.tipo]}{os.prioridade === 'urgente' && <span className="ml-2 text-red-700">· URGENTE</span>}</p>
          <p className="text-ink-muted">{nomes.pessoa ?? 'Sem cliente (rede)'}{nomes.contrato ? ` · ${nomes.contrato}` : ''}{nomes.cto ? ` · CTO ${nomes.cto}` : ''}</p>
          <p className="text-ink-muted">Técnico: {nomes.tecnico ?? '—'}{os.data_agendada ? ` · agendado ${formatarData(os.data_agendada)} ${os.hora_agendada?.slice(0, 5)}` : ' · sem agendamento'}</p>
        </div>
        <Distintivo tom={TOM_STATUS[os.status]}>{ROTULO_STATUS_OS[os.status]}</Distintivo>
      </div>

      <p className="rounded-md bg-surface/60 p-3 text-sm">{os.descricao}</p>
      {erro != null && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}

      {os.remarcacao_data && (
        <Alerta tipo="info" titulo={`Remarcação pedida: ${formatarData(os.remarcacao_data)} ${os.remarcacao_hora?.slice(0, 5)}`}>
          {os.remarcacao_motivo}
          <span className="mt-2 flex gap-2">
            <Botao variante="secundario" onClick={() => responder.mutate({ p_os_id: os.id, p_aprovar: true })} carregando={responder.isPending}>Aprovar</Botao>
            <Botao variante="secundario" onClick={() => responder.mutate({ p_os_id: os.id, p_aprovar: false })} carregando={responder.isPending}>Recusar</Botao>
          </span>
        </Alerta>
      )}

      {/* tempos: só o admin vê */}
      <div className="grid grid-cols-3 gap-2 rounded-md border border-line bg-surface/60 p-3 text-center text-sm">
        <div><p className="text-xs uppercase tracking-wide text-ink-muted">Tempo total</p><p className="font-semibold tabular-nums">{fmtMinutos(os.tempo_total_minutos)}</p><p className="text-xs text-ink-muted">do agendado ao fim</p></div>
        <div><p className="text-xs uppercase tracking-wide text-ink-muted">Execução</p><p className="font-semibold tabular-nums">{fmtMinutos(os.tempo_execucao_minutos)}</p><p className="text-xs text-ink-muted">início → fim</p></div>
        <div><p className="text-xs uppercase tracking-wide text-ink-muted">Pausas</p><p className="font-semibold tabular-nums">{fmtMinutos(os.tempo_pausa_minutos)}</p><p className="text-xs text-ink-muted">{os.data_ciencia ? 'ciência dada' : 'sem ciência'}</p></div>
      </div>

      {encerrado && (os.diagnostico || os.sinal_dbm != null || (materiais.data ?? []).length > 0) && (
        <div className="rounded-md border border-line p-3 text-sm">
          <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-ink-muted">Encerramento</p>
          {os.diagnostico && <p>Diagnóstico: <b>{ROTULO_DIAGNOSTICO[os.diagnostico]}</b>{os.sinal_dbm != null && <> · Sinal <b>{os.sinal_dbm} dBm</b></>}</p>}
          {(materiais.data ?? []).map((m) => (
            <p key={m.id} className="text-ink-muted">{nomes.item.get(m.item_id) ?? '—'} · {fmtQtd(m.quantidade)} · {formatarMoeda(m.valor_total)}</p>
          ))}
          {(materiais.data ?? []).length > 0 && <p className="font-medium">Material: {formatarMoeda((materiais.data ?? []).reduce((s, m) => s + m.valor_total, 0))}</p>}
          {os.avaliacao_resolvido != null && <p>Avaliação: {os.avaliacao_resolvido ? `resolvido, nota ${os.avaliacao_nota}` : 'não resolvido'}</p>}
          {os.comissao_lancamento_id && <p className="text-green-700">Comissão gerada no Contas a Pagar.</p>}
        </div>
      )}

      {/* ações por status */}
      <div className="flex flex-wrap gap-2">
        {aberto && !os.data_ciencia && <Botao variante="secundario" onClick={() => ciencia.mutate({ p_os_id: os.id })} carregando={ciencia.isPending}>Marcar ciência</Botao>}
        {aberto && !os.data_agendada && <Botao onClick={() => setPainel('agendar')}>Agendar</Botao>}
        {aberto && os.data_agendada && !os.remarcacao_data && <Botao variante="secundario" onClick={() => setPainel('remarcar')}>Pedir remarcação</Botao>}
        {aberto && os.data_agendada && <Botao onClick={() => iniciar.mutate({ p_os_id: os.id })} carregando={iniciar.isPending}>Iniciar atendimento</Botao>}
        {atendendo && <Botao variante="secundario" onClick={() => setPainel('pausar')}>Pausar</Botao>}
        {pausado && <Botao onClick={() => retomar.mutate({ p_os_id: os.id })} carregando={retomar.isPending}>Retomar</Botao>}
        {(atendendo || pausado) && <Botao onClick={() => { setLinhas([{ itemId: '', quantidade: '' }]); setPainel('encerrar') }}>Encerrar chamado</Botao>}
        {(aberto || atendendo || pausado) && <Botao variante="perigo" onClick={() => setPainel('cancelar')}>Cancelar</Botao>}
        {encerrado && os.avaliacao_resolvido == null && <Botao variante="secundario" onClick={() => setPainel('avaliar')}>Avaliar</Botao>}
        {encerrado && os.avaliacao_resolvido === false && (
          <Botao onClick={() => reabrir.mutate({ negocio_id: os.negocio_id, tipo: os.tipo, descricao: 'Reabertura: ' + os.descricao, pessoa_id: os.pessoa_id, contrato_id: os.contrato_id, tecnico_id: os.tecnico_id, cto_id: os.cto_id, prioridade: 'urgente', os_origem_id: os.id }, { onSuccess: aoFechar })} carregando={reabrir.isPending}>Reabrir chamado</Botao>
        )}
        {encerrado && !os.comissao_lancamento_id && (os.tipo === 'instalacao' || os.tipo === 'mudanca_endereco') && os.tecnico_id && (
          <Botao variante="secundario" onClick={() => setPainel('comissao')}>Gerar comissão</Botao>
        )}
      </div>

      {!encerrado && os.status !== 'cancelado' && (
        <div className="flex items-end gap-2">
          <div className="flex-1"><Selecao rotulo="Reatribuir técnico" opcoes={[{ valor: '', rotulo: 'Manter' }, ...(tecnicos.data ?? []).filter((t) => t.negocio_id === os.negocio_id && t.ativo && t.id !== os.tecnico_id).map((t) => ({ valor: t.id, rotulo: t.nome }))]} value={tecnicoNovo} onChange={(e) => setTecnicoNovo(e.target.value)} /></div>
          <Botao variante="secundario" disabled={!tecnicoNovo} carregando={atualizar.isPending} onClick={() => atualizar.mutate({ p_os_id: os.id, p_tecnico_id: tecnicoNovo }, { onSuccess: () => setTecnicoNovo('') })}>Aplicar</Botao>
        </div>
      )}

      {painel === 'agendar' && (
        <div className="flex items-end gap-2 rounded-md border border-line p-3">
          <Campo rotulo="Data" type="date" value={data} onChange={(e) => setData(e.target.value)} />
          <Campo rotulo="Hora" type="time" value={hora} onChange={(e) => setHora(e.target.value)} />
          <Botao onClick={() => agendar.mutate({ p_os_id: os.id, p_data: data, p_hora: hora }, fechar)} carregando={agendar.isPending}>Confirmar</Botao>
        </div>
      )}
      {painel === 'remarcar' && (
        <div className="space-y-2 rounded-md border border-line p-3">
          <div className="flex items-end gap-2">
            <Campo rotulo="Nova data" type="date" value={data} onChange={(e) => setData(e.target.value)} />
            <Campo rotulo="Hora" type="time" value={hora} onChange={(e) => setHora(e.target.value)} />
            <div className="flex-1"><Campo rotulo="Motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={300} /></div>
          </div>
          <Botao onClick={() => remarcar.mutate({ p_os_id: os.id, p_data: data, p_hora: hora, p_motivo: motivo }, fechar)} carregando={remarcar.isPending}>Solicitar</Botao>
        </div>
      )}
      {(painel === 'pausar' || painel === 'cancelar') && (
        <div className="flex items-end gap-2 rounded-md border border-line p-3">
          <div className="flex-1"><Campo rotulo="Motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={300} autoFocus /></div>
          <Botao variante={painel === 'cancelar' ? 'perigo' : 'primario'} disabled={motivo.trim().length < 3} carregando={pausar.isPending || cancelar.isPending}
            onClick={() => (painel === 'pausar' ? pausar.mutate({ p_os_id: os.id, p_motivo: motivo }, fechar) : cancelar.mutate({ p_os_id: os.id, p_motivo: motivo }, { onSuccess: aoFechar }))}>
            {painel === 'pausar' ? 'Pausar' : 'Cancelar chamado'}
          </Botao>
        </div>
      )}
      {painel === 'encerrar' && (
        <div className="space-y-3 rounded-md border border-line p-3">
          <p className="text-sm font-medium">Materiais usados (saem da bolsa do técnico; pode ficar negativa — reponha depois)</p>
          {linhas.map((l, i) => (
            <div key={i} className="flex items-end gap-2">
              <div className="flex-1"><Selecao rotulo={i === 0 ? 'Item' : ''} opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...itensNegocio.map((x) => ({ valor: x.id, rotulo: `${x.codigo} · ${x.nome}` }))]} value={l.itemId} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, itemId: e.target.value } : x)))} /></div>
              <input type="number" step="0.01" min="0.01" placeholder="Qtd." aria-label="Quantidade" value={l.quantidade} onChange={(e) => setLinhas((xs) => xs.map((x, j) => (j === i ? { ...x, quantidade: e.target.value } : x)))} className="h-10 w-24 rounded-md border border-line bg-white px-2 text-sm" />
              <button type="button" aria-label="Remover" className="pb-2 text-ink-muted hover:text-red-700" onClick={() => setLinhas((xs) => xs.filter((_, j) => j !== i))}>×</button>
            </div>
          ))}
          <Botao variante="secundario" onClick={() => setLinhas((xs) => [...xs, { itemId: '', quantidade: '' }])}>+ Material</Botao>
          <div className="grid grid-cols-3 gap-4">
            <Selecao rotulo="Diagnóstico" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...Object.entries(ROTULO_DIAGNOSTICO).map(([v, r]) => ({ valor: v, rotulo: r }))]} value={diagnostico} onChange={(e) => setDiagnostico(e.target.value)} />
            <Campo rotulo="Sinal (dBm, opcional)" type="number" step="0.1" value={sinal} onChange={(e) => setSinal(e.target.value)} placeholder="-18.5" />
            <Campo rotulo="Observação (opcional)" value={obsFim} onChange={(e) => setObsFim(e.target.value)} maxLength={500} />
          </div>
          <Botao carregando={encerrar.isPending} onClick={() => encerrar.mutate({
            p_os_id: os.id,
            p_itens: linhas.filter((l) => l.itemId && Number(l.quantidade.replace(',', '.')) > 0).map((l) => ({ item_id: l.itemId, quantidade: Number(l.quantidade.replace(',', '.')) })),
            p_diagnostico: diagnostico || null, p_sinal_dbm: sinal.trim() ? Number(sinal.replace(',', '.')) : null, p_observacao: obsFim.trim() || null,
          }, fechar)}>Confirmar encerramento</Botao>
        </div>
      )}
      {painel === 'avaliar' && (
        <div className="flex items-end gap-2 rounded-md border border-line p-3">
          <Selecao rotulo="Foi resolvido?" opcoes={[{ valor: 'sim', rotulo: 'Sim' }, { valor: 'nao', rotulo: 'Não' }]} value={resolvido} onChange={(e) => setResolvido(e.target.value)} />
          {resolvido === 'sim' && <Selecao rotulo="Nota" opcoes={['5', '4', '3', '2', '1'].map((n) => ({ valor: n, rotulo: n }))} value={nota} onChange={(e) => setNota(e.target.value)} />}
          <Botao carregando={avaliar.isPending} onClick={() => avaliar.mutate({ p_os_id: os.id, p_resolvido: resolvido === 'sim', p_nota: resolvido === 'sim' ? Number(nota) : null }, fechar)}>Salvar avaliação</Botao>
        </div>
      )}
      {painel === 'comissao' && (
        <div className="space-y-2 rounded-md border border-line p-3">
          <p className="text-sm">Comissão de {nomes.tecnico}: padrão 50% da mensalidade do contrato. Vai como despesa prevista na categoria Comissões.</p>
          <div className="flex items-end gap-2">
            <div className="flex-1"><Selecao rotulo="Conta" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(contas.data ?? []).filter((c) => c.ativo && c.tipo !== 'credito').map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} /></div>
            <Campo rotulo="Vencimento" type="date" value={venc} onChange={(e) => setVenc(e.target.value)} />
            <Campo rotulo="Valor (vazio = 50%)" type="number" step="0.01" min="0" value={valorCom} onChange={(e) => setValorCom(e.target.value)} />
            <Botao disabled={!contaId} carregando={comissao.isPending} onClick={() => comissao.mutate({ p_os_id: os.id, p_conta_id: contaId, p_vencimento: venc, p_valor: valorCom.trim() ? Number(valorCom.replace(',', '.')) : null }, fechar)}>Gerar</Botao>
          </div>
        </div>
      )}

      <div className="rounded-md border border-line p-3">
        <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-ink-muted">Histórico</p>
        <ul className="space-y-1 text-xs text-ink-muted">
          {(historico.data ?? []).map((h) => (
            <li key={h.id}><span className="tabular-nums">{new Date(h.criado_em).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}</span> · <b>{ROTULO_EVENTO_OS[h.evento]}</b>{h.observacao ? ` — ${h.observacao}` : ''}</li>
          ))}
        </ul>
      </div>
      <fieldset disabled={ocupado} className="hidden" />
    </div>
  )
}
