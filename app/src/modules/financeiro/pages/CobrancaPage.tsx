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
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useContratos } from '../../contratos/api'
import { codigoContrato } from '../../contratos/tipos'

interface Bloqueio { id: string; negocio_id: string; contrato_id: string; pessoa_id: string; tipo: 'bloqueio' | 'desbloqueio'; status: string; motivo: string; criado_em: string }
interface PixCobranca { id: string; negocio_id: string; pessoa_id: string | null; valor: number; status: string; criado_em: string; pago_em: string | null }

/** Cobrança: bloqueio assistido (lista de quem bloquear/desbloquear) e Pix recentes. */
export function CobrancaPage() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  const negocios = useNegocios()
  const pessoas = usePessoas()
  const contratos = useContratos()
  const [negocioId, setNegocioId] = useState('')
  const servnet = (negocios.data ?? []).find((n) => n.nome.toLowerCase().includes('servnet')) ?? (negocios.data ?? [])[0]
  const negocioAtual = negocioId || servnet?.id || ''

  const bloqueios = useQuery({
    queryKey: ['cobranca', organizacao.id, 'bloqueios'],
    queryFn: async (): Promise<Bloqueio[]> => {
      const { data, error } = await supabase.from('bloqueios').select('id, negocio_id, contrato_id, pessoa_id, tipo, status, motivo, criado_em').eq('organizacao_id', organizacao.id).eq('status', 'pendente').order('criado_em')
      if (error) throw error
      return (data ?? []) as Bloqueio[]
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
  const descartar = useMutation({
    mutationFn: async (id: string) => { const { error } = await supabase.rpc('descartar_bloqueio', { p_id: id }); if (error) throw error },
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

  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const rotuloContrato = (id: string) => { const c = (contratos.data ?? []).find((x) => x.id === id); return c ? codigoContrato(c) : '—' }
  const lista = (bloqueios.data ?? []).filter((b) => b.negocio_id === negocioAtual)
  const pixLista = (pix.data ?? []).filter((p) => p.negocio_id === negocioAtual)
  const erro = gerar.error ?? executar.error ?? descartar.error

  return (
    <>
      <CabecalhoPagina titulo="Cobrança" descricao="Bloqueio assistido e pagamentos Pix"
        acoes={
          <span className="flex items-center gap-2">
            <select aria-label="Negócio" value={negocioAtual} onChange={(e) => setNegocioId(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
              {(negocios.data ?? []).filter((n) => n.ativo).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
            </select>
            <Botao variante="secundario" onClick={() => gerar.mutate()} carregando={gerar.isPending}>Atualizar lista</Botao>
          </span>
        } />
      {erro != null && <div className="mb-4"><Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta></div>}

      <div className="space-y-6">
        <Cartao className="p-0">
          <div className="border-b border-line px-6 py-3">
            <h2 className="text-sm font-semibold">Ações na rede ({lista.length})</h2>
            <p className="text-xs text-ink-muted">Bloqueie/desbloqueie o cliente no seu sistema de rede e marque como executado — o contrato muda de status sozinho (ativo ↔ suspenso).</p>
          </div>
          {bloqueios.isPending ? <div className="p-6"><Carregando /></div> : lista.length === 0 ? (
            <p className="px-6 py-10 text-center text-sm text-ink-muted">Nada para bloquear ou desbloquear agora. 👍</p>
          ) : (
            <ul className="divide-y divide-line text-sm">
              {lista.map((b) => (
                <li key={b.id} className="flex flex-wrap items-center justify-between gap-2 px-6 py-3">
                  <span className="min-w-0">
                    <Distintivo tom={b.tipo === 'bloqueio' ? 'alerta' : 'ok'}>{b.tipo === 'bloqueio' ? 'Bloquear' : 'Desbloquear'}</Distintivo>
                    <span className="ml-2 font-medium">{nomePessoa.get(b.pessoa_id) ?? '—'}</span>
                    <span className="ml-2 text-xs text-ink-muted">{rotuloContrato(b.contrato_id)} · {b.motivo}</span>
                  </span>
                  <span className="flex shrink-0 gap-2">
                    <Botao variante="secundario" carregando={descartar.isPending} onClick={() => descartar.mutate(b.id)}>Ignorar</Botao>
                    <Botao carregando={executar.isPending} onClick={() => executar.mutate(b.id)}>{b.tipo === 'bloqueio' ? 'Bloqueei na rede' : 'Desbloqueei na rede'}</Botao>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Cartao>

        <Cartao className="p-0">
          <div className="flex items-center justify-between border-b border-line px-6 py-3">
            <h2 className="text-sm font-semibold">Pix recentes</h2>
            {reconciliado && <span className="text-xs text-ink-muted">{reconciliado.verificados > 0 ? `Reconciliação: ${reconciliado.verificados} verificados no Mercado Pago · ${reconciliado.confirmados} baixados agora` : 'Reconciliação: nenhum Pix antigo aguardando'}</span>}
          </div>
          {pixLista.length === 0 ? <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhuma cobrança Pix ainda. Ative o Pix automático em Portal → Configurar e coloque o token do Mercado Pago nos secrets.</p> : (
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
