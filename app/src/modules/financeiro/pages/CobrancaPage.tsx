import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Distintivo } from '../../../core/ui/Distintivo'
import { Carregando } from '../../../core/ui/Carregando'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../../core/formatos'
import { supabase } from '../../../core/supabase/client'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { Link } from 'react-router'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useContratos } from '../../contratos/api'
import { useConfigsNotificacao } from '../../notificacoes/api'
import { BarraFiltros, CampoBusca, ContagemFiltro, SelectFiltro } from '../../../core/ui/Filtros'
import { codigoContrato } from '../../contratos/tipos'

interface Bloqueio { id: string; negocio_id: string; contrato_id: string; pessoa_id: string; tipo: 'bloqueio' | 'desbloqueio'; status: string; motivo: string; confianca_furada: boolean; criado_em: string }
interface Confianca { id: string; negocio_id: string; contrato_id: string; pessoa_id: string; segurar_ate: string; observacao: string | null; status: string }
interface PixCobranca { id: string; negocio_id: string; pessoa_id: string | null; valor: number; status: string; criado_em: string; pago_em: string | null }

/** Cobrança: bloqueio assistido (lista de quem bloquear/desbloquear) e Pix recentes. */
export function CobrancaPage() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  const negocios = useNegocios()
  const pessoas = usePessoas()
  const contratos = useContratos()
  const configs = useConfigsNotificacao()
  const [negocioId, setNegocioId] = useState('')
  const [buscaPix, setBuscaPix] = useState(''); const [statusPix, setStatusPix] = useState('')
  const [buscaConfianca, setBuscaConfianca] = useState('')
  const servnet = (negocios.data ?? []).find((n) => n.nome.toLowerCase().includes('servnet')) ?? (negocios.data ?? [])[0]
  const negocioAtual = negocioId || servnet?.id || ''

  const bloqueios = useQuery({
    queryKey: ['cobranca', organizacao.id, 'bloqueios'],
    queryFn: async (): Promise<Bloqueio[]> => {
      const { data, error } = await supabase.from('bloqueios').select('id, negocio_id, contrato_id, pessoa_id, tipo, status, motivo, confianca_furada, criado_em').eq('organizacao_id', organizacao.id).eq('status', 'pendente').order('criado_em')
      if (error) throw error
      return (data ?? []) as Bloqueio[]
    },
  })
  const confiancas = useQuery({
    queryKey: ['cobranca', organizacao.id, 'confiancas'],
    queryFn: async (): Promise<Confianca[]> => {
      const { data, error } = await supabase.from('confiancas').select('id, negocio_id, contrato_id, pessoa_id, segurar_ate, observacao, status').eq('organizacao_id', organizacao.id).eq('status', 'ativa').order('segurar_ate')
      if (error) throw error
      return (data ?? []) as Confianca[]
    },
  })
  const pix = useQuery({
    queryKey: ['cobranca', organizacao.id, 'pix'],
    queryFn: async (): Promise<PixCobranca[]> => {
      const { data, error } = await supabase.from('pix_cobrancas').select('id, negocio_id, pessoa_id, valor, status, criado_em, pago_em').eq('organizacao_id', organizacao.id).order('criado_em', { ascending: false }).limit(50)
      if (error) throw error
      return (data ?? []).map((p) => ({ ...p, valor: Number(p.valor) })) as PixCobranca[]
    },
  })
  const invalidar = () => { void qc.invalidateQueries({ queryKey: ['cobranca', organizacao.id] }); void qc.invalidateQueries({ queryKey: ['contratos', organizacao.id] }) }
  const gerar = useMutation({
    mutationFn: async () => { const { error } = await supabase.rpc('gerar_bloqueios', { p_negocio_id: negocioAtual }); if (error) throw error },
    onSuccess: invalidar,
  })
  const executar = useMutation({
    mutationFn: async (id: string) => { const { error } = await supabase.rpc('executar_bloqueio', { p_id: id }); if (error) throw error },
    onSuccess: invalidar,
  })
  // botão manual do bloqueio automático: não esperar o robô das 00:00 — útil pra quem está lançando contratos/baixas ao longo do dia
  const executarAgora = useMutation({
    mutationFn: async (): Promise<{ executados: number }> => {
      const { data, error } = await supabase.rpc('executar_bloqueios_agora', { p_negocio_id: negocioAtual })
      if (error) throw error
      return data as { executados: number }
    },
    onSuccess: invalidar,
  })
  const descartar = useMutation({
    mutationFn: async (id: string) => { const { error } = await supabase.rpc('descartar_bloqueio', { p_id: id }); if (error) throw error },
    onSuccess: invalidar,
  })
  // voto de confiança: segura o bloqueio até a data escolhida
  const [confiando, setConfiando] = useState<Bloqueio | null>(null)
  const [confAte, setConfAte] = useState('')
  const [confObs, setConfObs] = useState('')
  const darConfianca = useMutation({
    mutationFn: async () => {
      if (!confiando) return
      const { error } = await supabase.rpc('dar_confianca', { p_contrato_id: confiando.contrato_id, p_segurar_ate: confAte, p_observacao: confObs || null })
      if (error) throw error
    },
    onSuccess: () => { setConfiando(null); setConfAte(''); setConfObs(''); invalidar() },
  })
  const cancelarConfianca = useMutation({
    mutationFn: async (id: string) => { const { error } = await supabase.rpc('cancelar_confianca', { p_id: id }); if (error) throw error },
    onSuccess: invalidar,
  })

  // reconciliação ativa do Pix: ao abrir a tela, re-consulta no Mercado Pago os
  // "aguardando" com mais de 1h (webhook pode ter se perdido) — nunca bloquear quem pagou
  const [reconciliado, setReconciliado] = useState<{ verificados: number; confirmados: number } | null>(null)
  useEffect(() => {
    let ativo = true
    supabase.functions.invoke('pix-reconciliar', { body: {} })
      .then(({ data }) => { if (ativo && data?.ok) { setReconciliado({ verificados: data.verificados, confirmados: data.confirmados }); if (data.confirmados > 0) invalidar() } })
      .catch(() => { /* Edge indisponível: a tela segue com os dados do banco */ })
    return () => { ativo = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  // atualiza a lista ao abrir a tela
  useEffect(() => { if (negocioAtual) gerar.mutate() }, [negocioAtual]) // eslint-disable-line react-hooks/exhaustive-deps

  const [busca, setBusca] = useState('')
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const rotuloContrato = (id: string) => { const c = (contratos.data ?? []).find((x) => x.id === id); return c ? codigoContrato(c) : '—' }
  const buscaNorm = busca.trim().toLowerCase()
  const listaTodas = (bloqueios.data ?? []).filter((b) => b.negocio_id === negocioAtual)
  const lista = listaTodas.filter((b) => !buscaNorm || (nomePessoa.get(b.pessoa_id) ?? '').toLowerCase().includes(buscaNorm) || rotuloContrato(b.contrato_id).toLowerCase().includes(buscaNorm))
  const pixTodos = (pix.data ?? []).filter((p) => p.negocio_id === negocioAtual)
  // Pix acumula rápido: filtro de situação e busca por cliente
  const termoPix = buscaPix.trim().toLowerCase()
  const pixLista = pixTodos.filter((p) => {
    if (statusPix && p.status !== statusPix) return false
    if (!termoPix) return true
    return (nomePessoa.get(p.pessoa_id ?? '') ?? '').toLowerCase().includes(termoPix)
  })
  const confTodas = (confiancas.data ?? []).filter((c) => c.negocio_id === negocioAtual)
  const termoConf = buscaConfianca.trim().toLowerCase()
  const confLista = confTodas.filter((c) => !termoConf
    || (nomePessoa.get(c.pessoa_id) ?? '').toLowerCase().includes(termoConf)
    || rotuloContrato(c.contrato_id).toLowerCase().includes(termoConf))
  const configAtual = (configs.data ?? []).find((c) => c.negocio_id === negocioAtual)
  const erro = gerar.error ?? executar.error ?? executarAgora.error ?? descartar.error ?? darConfianca.error ?? cancelarConfianca.error

  return (
    <>
      <CabecalhoPagina titulo="Cobrança" descricao="Bloqueio assistido e pagamentos Pix"
        acoes={
          <span className="flex items-center gap-2">
            <select aria-label="Negócio" value={negocioAtual} onChange={(e) => setNegocioId(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
              {(negocios.data ?? []).filter((n) => n.ativo).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
            </select>
            <Botao variante="secundario" onClick={() => gerar.mutate()} carregando={gerar.isPending}>Atualizar lista</Botao>
            {configAtual?.bloqueio_automatico && (
              <Botao onClick={() => executarAgora.mutate()} carregando={executarAgora.isPending}>Atualizar bloqueio/desbloqueio agora</Botao>
            )}
          </span>
        } />
      {erro != null && <div className="mb-4"><Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta></div>}
      {executarAgora.isSuccess && (
        <div className="mb-4"><Alerta tipo="sucesso">{executarAgora.data.executados ? `${executarAgora.data.executados} contrato(s) atualizado(s) agora.` : 'Nada para atualizar agora — está tudo em dia.'}</Alerta></div>
      )}
      {configAtual?.bloqueio_automatico && (
        <div className="mb-4">
          <Alerta tipo="info">
            Bloqueio automático ligado para este negócio: todo dia às 00:00 o sistema confirma sozinho — por isso a lista abaixo costuma estar vazia.
            Precisa antes disso? Use "Atualizar bloqueio/desbloqueio agora" acima. Histórico em <Link to="/relatorios/bloqueios" className="underline">Relatórios → Bloqueios e desbloqueios</Link>.
          </Alerta>
        </div>
      )}

      <div className="space-y-6">
        <Cartao className="p-0">
          <div className="border-b border-line px-6 py-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h2 className="text-sm font-semibold">Ações na rede ({buscaNorm ? `${lista.length} de ${listaTodas.length}` : listaTodas.length})</h2>
              {listaTodas.length > 0 && (
                <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar cliente ou nº do contrato…" className="h-9 w-64 rounded-md border border-line bg-white px-3 text-sm" />
              )}
            </div>
            <p className="text-xs text-ink-muted">Bloqueie/desbloqueie o cliente no seu sistema de rede e marque como executado — o contrato muda de status sozinho (ativo ↔ suspenso).</p>
          </div>
          {bloqueios.isPending ? <div className="p-6"><Carregando /></div> : listaTodas.length === 0 ? (
            <p className="px-6 py-10 text-center text-sm text-ink-muted">Nada para bloquear ou desbloquear agora. 👍</p>
          ) : lista.length === 0 ? (
            <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhum resultado para "{busca}".</p>
          ) : (
            <ul className="divide-y divide-line text-sm">
              {lista.map((b) => (
                <li key={b.id} className="px-6 py-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="min-w-0">
                      <Distintivo tom={b.tipo === 'bloqueio' ? 'alerta' : 'ok'}>{b.tipo === 'bloqueio' ? 'Bloquear' : 'Desbloquear'}</Distintivo>
                      {b.confianca_furada && <span className="ml-2"><Distintivo tom="alerta">🤝 Confiança furada</Distintivo></span>}
                      <span className="ml-2 font-medium">{nomePessoa.get(b.pessoa_id) ?? '—'}</span>
                      <span className="ml-2 text-xs text-ink-muted">{rotuloContrato(b.contrato_id)} · {b.motivo}</span>
                    </span>
                    <span className="flex shrink-0 gap-2">
                      {b.tipo === 'bloqueio' && <Botao variante="secundario" onClick={() => { setConfiando(confiando?.id === b.id ? null : b); setConfAte(''); setConfObs('') }}>🤝 Confiança</Botao>}
                      <Botao variante="secundario" carregando={descartar.isPending} onClick={() => descartar.mutate(b.id)}>Ignorar</Botao>
                      <Botao carregando={executar.isPending} onClick={() => executar.mutate(b.id)}>{b.tipo === 'bloqueio' ? 'Bloqueei na rede' : 'Desbloqueei na rede'}</Botao>
                    </span>
                  </div>
                  {confiando?.id === b.id && (
                    <form className="mt-3 flex flex-wrap items-end gap-2 rounded-md bg-canvas p-3" onSubmit={(e) => { e.preventDefault(); darConfianca.mutate() }}>
                      <label className="text-xs text-ink-muted">Segurar o bloqueio até
                        <input type="date" required value={confAte} min={new Date(Date.now() + 86400000).toISOString().slice(0, 10)} onChange={(e) => setConfAte(e.target.value)} className="mt-1 block h-9 rounded-md border border-line bg-white px-2 text-sm text-ink" />
                      </label>
                      <label className="min-w-48 flex-1 text-xs text-ink-muted">Combinado (opcional)
                        <input value={confObs} onChange={(e) => setConfObs(e.target.value)} placeholder="Ex.: prometeu pagar no dia 15" className="mt-1 block h-9 w-full rounded-md border border-line bg-white px-2 text-sm text-ink" />
                      </label>
                      <Botao type="submit" carregando={darConfianca.isPending}>Dar confiança</Botao>
                    </form>
                  )}
                </li>
              ))}
            </ul>
          )}
        </Cartao>

        {confTodas.length > 0 && (
          <Cartao className="p-0">
            <div className="border-b border-line px-6 py-3">
              <h2 className="text-sm font-semibold">Confianças ativas ({confTodas.length})</h2>
              <p className="text-xs text-ink-muted">Bloqueio segurado até a data combinada. Pagou → cumprida; passou devendo → volta na lista como confiança furada.</p>
            </div>
            {confTodas.length > 6 && <BarraFiltros><CampoBusca valor={buscaConfianca} aoMudar={setBuscaConfianca} rotulo="Buscar por cliente ou contrato" /><ContagemFiltro visiveis={confLista.length} total={confTodas.length} singular="confiança" plural="confianças" /></BarraFiltros>}
            <ul className="divide-y divide-line text-sm">
              {confLista.map((c) => (
                <li key={c.id} className="flex flex-wrap items-center justify-between gap-2 px-6 py-3">
                  <span className="min-w-0">
                    <span className="font-medium">{nomePessoa.get(c.pessoa_id) ?? '—'}</span>
                    <span className="ml-2 text-xs text-ink-muted">{rotuloContrato(c.contrato_id)} · até {formatarData(c.segurar_ate)}{c.observacao ? ` · ${c.observacao}` : ''}</span>
                  </span>
                  <Botao variante="secundario" carregando={cancelarConfianca.isPending} onClick={() => cancelarConfianca.mutate(c.id)}>Cancelar</Botao>
                </li>
              ))}
            </ul>
          </Cartao>
        )}

        <Cartao className="p-0">
          <div className="flex items-center justify-between border-b border-line px-6 py-3">
            <h2 className="text-sm font-semibold">Pix recentes</h2>
            {reconciliado && <span className="text-xs text-ink-muted">{reconciliado.verificados > 0 ? `Reconciliação: ${reconciliado.verificados} verificados no Mercado Pago · ${reconciliado.confirmados} baixados agora` : 'Reconciliação: nenhum Pix antigo aguardando'}</span>}
          </div>
          <BarraFiltros>
            <CampoBusca valor={buscaPix} aoMudar={setBuscaPix} rotulo="Buscar por cliente" />
            <SelectFiltro valor={statusPix} aoMudar={setStatusPix} rotulo="Filtrar por situação do Pix">
              <option value="">Todas as situações</option>
              <option value="pendente">Aguardando</option>
              <option value="pago">Pagos</option>
              <option value="cancelado">Cancelados</option>
            </SelectFiltro>
            <ContagemFiltro visiveis={pixLista.length} total={pixTodos.length} singular="cobrança" plural="cobranças" />
          </BarraFiltros>
          {pixLista.length === 0 ? <p className="px-6 py-10 text-center text-sm text-ink-muted">{pixTodos.length === 0 ? 'Nenhuma cobrança Pix ainda. Ative o Pix automático em Portal → Configurar e coloque o token do Mercado Pago nos secrets.' : 'Nenhuma cobrança Pix com esses filtros.'}</p> : (
            <ul className="divide-y divide-line text-sm">
              {pixLista.map((p) => (
                <li key={p.id} className="flex items-center justify-between px-6 py-3">
                  <span><span className="font-medium">{nomePessoa.get(p.pessoa_id ?? '') ?? '—'}</span> <span className="text-xs text-ink-muted">· {formatarData(p.criado_em.slice(0, 10))}</span></span>
                  <span className="flex items-center gap-3">
                    <span className="tabular-nums">{formatarMoeda(p.valor)}</span>
                    <Distintivo tom={p.status === 'pago' ? 'ok' : p.status === 'pendente' ? 'info' : 'neutro'}>{p.status === 'pago' ? `Pago ${p.pago_em ? formatarData(p.pago_em.slice(0, 10)) : ''}` : p.status === 'pendente' ? 'Aguardando' : p.status}</Distintivo>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Cartao>
      </div>
    </>
  )
}
