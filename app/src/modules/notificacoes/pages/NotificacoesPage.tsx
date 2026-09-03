import { useMemo, useState } from 'react'
import { Link } from 'react-router'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useConfigsNotificacao, useExecutarNotificacoes, useNotificacoes } from '../api'
import { FormularioConfig } from '../components/FormularioConfig'
import { EnviarTeste } from '../components/EnviarTeste'
import { ROTULO_PROVEDOR, ROTULO_STATUS, ROTULO_TIPO, type StatusNotificacao, type TipoNotificacao } from '../tipos'

type Janela = 'config' | 'teste' | null
const TOM: Record<StatusNotificacao, 'ok' | 'alerta' | 'neutro' | 'info'> = { simulado: 'info', enviado: 'ok', pendente: 'alerta', erro: 'neutro' }

export function NotificacoesPage() {
  const negocios = useNegocios()
  const configs = useConfigsNotificacao()
  const pessoas = usePessoas()
  const executar = useExecutarNotificacoes()
  const [negocioSel, setNegocioSel] = useState('')
  const [janela, setJanela] = useState<Janela>(null)
  const [filtroTipo, setFiltroTipo] = useState<TipoNotificacao | ''>('')
  const [filtroStatus, setFiltroStatus] = useState<StatusNotificacao | ''>('')
  const [busca, setBusca] = useState('')

  const ativos = useMemo(() => (negocios.data ?? []).filter((n) => n.ativo), [negocios.data])
  const negocio = ativos.find((n) => n.id === negocioSel) ?? ativos[0] ?? null
  const config = (configs.data ?? []).find((c) => c.negocio_id === negocio?.id) ?? null
  const log = useNotificacoes(negocio?.id ?? null)
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const lista = (log.data ?? []).filter((n) =>
    (!filtroTipo || n.tipo === filtroTipo) && (!filtroStatus || n.status === filtroStatus)
    && (!busca || n.pessoa.toLowerCase().includes(busca.toLowerCase()) || (n.contrato_codigo !== null && `#${String(n.contrato_codigo).padStart(3, '0')}`.includes(busca))))
  const fechar = () => setJanela(null)

  if (negocios.isPending || configs.isPending) return <><CabecalhoPagina titulo="Notificações" /><Carregando /></>
  if (negocios.isError || configs.isError) return <><CabecalhoPagina titulo="Notificações" /><Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(negocios.error ?? configs.error)}</Alerta></>

  return (
    <>
      <CabecalhoPagina
        titulo="Notificações"
        descricao="Avisos de cobrança por WhatsApp: antes do vencimento, no dia e no bloqueio (modo simulado)"
        acoes={negocio && config ? (
          <>
            <Botao variante="secundario" onClick={() => setJanela('teste')}>Enviar teste</Botao>
            <Botao onClick={() => executar.mutate(undefined)} carregando={executar.isPending} disabled={!config.ativo}>Executar verificação agora</Botao>
          </>
        ) : undefined}
      />
      {!negocio && <Alerta tipo="info" titulo="Nenhum negócio ativo">Cadastre um negócio em <Link to="/negocios" className="underline">Negócios</Link> para configurar avisos.</Alerta>}
      {negocio && (
        <div className="space-y-6">
          <div className="flex flex-wrap items-center gap-3">
            {ativos.length > 1 && (
              <select aria-label="Negócio" value={negocio.id} onChange={(e) => setNegocioSel(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
                {ativos.map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
              </select>
            )}
            {config ? (
              <span className="text-sm text-ink-muted">{negocio.nome} · {config.numero_whatsapp ?? 'sem número'} · {config.dias_antes} dia(s) antes · bloqueio {config.dias_apos} dia(s) após · {config.hora_inicio.slice(0, 5)}–{config.hora_fim.slice(0, 5)} · {ROTULO_PROVEDOR[config.provedor]}{config.instancia ? ` (${config.instancia})` : ''}</span>
            ) : <span className="text-sm text-ink-muted">{negocio.nome} · sem configuração</span>}
            {config && <Distintivo tom={config.ativo ? 'ok' : 'neutro'}>{config.ativo ? 'Ativas' : 'Desativadas'}</Distintivo>}
            <Botao variante="secundario" className="ml-auto" onClick={() => setJanela('config')}>{config ? 'Configurar' : 'Configurar notificações'}</Botao>
          </div>
          {executar.data && (
            <Alerta tipo="sucesso" titulo={`Verificação de ${formatarData(executar.data.data)} concluída`}>
              {executar.data.geradas} aviso(s) gerado(s), {executar.data.processadas} processado(s) em modo simulado, {executar.data.pendentes} pendente(s) (fora do horário comercial).
            </Alerta>
          )}
          {executar.error && <Alerta tipo="erro">{mensagemDeErro(executar.error)}</Alerta>}
          {!config && <Alerta tipo="info" titulo="Sem configuração">Defina o número, os dias e as mensagens deste negócio. Nada é enviado de verdade nesta etapa.</Alerta>}
          {config && !config.ativo && <Alerta tipo="info">Notificações desativadas para este negócio. O job diário não gera avisos até ativar.</Alerta>}

          <Cartao className="p-0">
            <div className="flex flex-wrap items-center gap-3 border-b border-line px-6 py-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Histórico</h2>
              <input aria-label="Buscar cliente ou contrato" value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Cliente ou #contrato" className="h-9 rounded-md border border-line bg-white px-3 text-sm" />
              <select aria-label="Filtrar por evento" value={filtroTipo} onChange={(e) => setFiltroTipo(e.target.value as TipoNotificacao | '')} className="h-9 rounded-md border border-line bg-white px-3 text-sm">
                <option value="">Todos os eventos</option>
                {(Object.keys(ROTULO_TIPO) as TipoNotificacao[]).map((t) => <option key={t} value={t}>{ROTULO_TIPO[t]}</option>)}
              </select>
              <select aria-label="Filtrar por status" value={filtroStatus} onChange={(e) => setFiltroStatus(e.target.value as StatusNotificacao | '')} className="h-9 rounded-md border border-line bg-white px-3 text-sm">
                <option value="">Todos os status</option>
                {(Object.keys(ROTULO_STATUS) as StatusNotificacao[]).map((s) => <option key={s} value={s}>{ROTULO_STATUS[s]}</option>)}
              </select>
              <span className="ml-auto text-sm text-ink-muted">{lista.length} registro(s)</span>
            </div>
            {log.isPending && config ? <div className="p-6"><Carregando /></div> : lista.length === 0 ? (
              <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhuma notificação registrada. Use "Executar verificação agora" ou "Enviar teste".</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-6 py-3 font-medium">Registro</th><th className="px-6 py-3 font-medium">Cliente</th><th className="px-6 py-3 font-medium">Evento</th><th className="px-6 py-3 font-medium">Vencimento</th><th className="px-6 py-3 font-medium">Destino</th><th className="px-6 py-3 font-medium">Status</th><th className="px-6 py-3 font-medium">Mensagem</th></tr></thead>
                  <tbody>
                    {lista.map((n) => (
                      <tr key={n.id} className="border-b border-line align-top last:border-0">
                        <td className="px-6 py-3 tabular-nums text-ink-muted whitespace-nowrap">{formatarData(n.criado_em.slice(0, 10))}</td>
                        <td className="px-6 py-3 font-medium whitespace-nowrap">{nomePessoa.get(n.pessoa_id) ?? n.pessoa}{n.contrato_codigo !== null && <span className="ml-1 font-mono text-xs text-ink-muted">#{String(n.contrato_codigo).padStart(3, '0')}</span>}</td>
                        <td className="px-6 py-3 whitespace-nowrap">{ROTULO_TIPO[n.tipo]}</td>
                        <td className="px-6 py-3 tabular-nums whitespace-nowrap">{formatarData(n.data_referencia)}</td>
                        <td className="px-6 py-3 font-mono text-xs whitespace-nowrap">{n.numero_destino ?? '—'}</td>
                        <td className="px-6 py-3"><Distintivo tom={TOM[n.status]}>{ROTULO_STATUS[n.status]}</Distintivo>{n.erro && <p className="mt-1 text-xs text-ink-muted">{n.erro}</p>}</td>
                        <td className="max-w-md px-6 py-3 text-xs text-ink-muted">{n.mensagem}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Cartao>
        </div>
      )}
      {negocio && (
        <Modal aberto={janela !== null} aoFechar={fechar} titulo={janela === 'teste' ? 'Enviar mensagem de teste' : `Notificações · ${negocio.nome}`}>
          {janela === 'config' && <FormularioConfig negocioId={negocio.id} negocioNome={negocio.nome} config={config} aoConcluir={fechar} />}
          {janela === 'teste' && <EnviarTeste negocioId={negocio.id} pessoas={pessoas.data ?? []} aoConcluir={fechar} />}
        </Modal>
      )}
    </>
  )
}
