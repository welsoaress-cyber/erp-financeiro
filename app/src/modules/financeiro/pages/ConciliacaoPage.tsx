import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { SeletorMes } from '../../../core/ui/SeletorMes'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { fimDoMes, formatarData, formatarMoeda } from '../../../core/formatos'
import { supabase } from '../../../core/supabase/client'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { usePeriodo } from '../../../core/periodo/usePeriodo'
import { useContas } from '../../contas/api'
import { BarraFiltros, CampoBusca, ContagemFiltro, SelectFiltro } from '../../../core/ui/Filtros'

interface MovConciliacao { id: string; lancamento_id: string; valor: number; data: string; conciliado_em: string | null; descricao: string; pessoa: string | null }

function useMovimentosConta(contaId: string, mes: string) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: ['conciliacao', organizacao.id, contaId, mes],
    enabled: Boolean(contaId),
    queryFn: async (): Promise<MovConciliacao[]> => {
      const { data, error } = await supabase
        .from('movimentos')
        .select('id, lancamento_id, valor, data, conciliado_em, lancamentos(descricao, pessoas(nome))')
        .eq('organizacao_id', organizacao.id)
        .eq('conta_id', contaId)
        .gte('data', mes)
        .lte('data', fimDoMes(mes))
        .order('data')
      if (error) throw error
      return (data ?? []).map((m) => {
        const lanc = m.lancamentos as unknown as { descricao: string; pessoas: { nome: string } | null } | null
        return {
          id: m.id, lancamento_id: m.lancamento_id, valor: Number(m.valor), data: m.data, conciliado_em: m.conciliado_em,
          descricao: lanc?.descricao ?? '—', pessoa: lanc?.pessoas?.nome ?? null,
        }
      })
    },
  })
}

function useConciliar() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (p: { ids: string[]; conciliar: boolean }) => {
      const { error } = await supabase.rpc('conciliar_movimentos', { p_ids: p.ids, p_conciliar: p.conciliar })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['conciliacao', organizacao.id] }),
  })
}

/** Ajustar baixa: move um lançamento já efetivado pra outra conta (ex.: marcado no Mercado Pago, caiu na Caixa). */
function useCorrigirConta() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (p: { lancamentoId: string; contaId: string }) => {
      const { error } = await supabase.rpc('corrigir_conta_lancamento', { p_id: p.lancamentoId, p_conta_id: p.contaId })
      if (error) throw error
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['conciliacao', organizacao.id] }),
  })
}

/** Conciliação bancária: conferir os movimentos de cada conta contra o extrato, mês a mês. */
export function ConciliacaoPage() {
  const { mes, setMes } = usePeriodo()
  const contas = useContas()
  const [contaId, setContaId] = useState('')
  const [busca, setBusca] = useState('')
  const [situacao, setSituacao] = useState<'' | 'pendente' | 'conferido'>('')
  const [sinal, setSinal] = useState<'' | 'entrada' | 'saida'>('')
  const [dia, setDia] = useState('')
  const [movendoId, setMovendoId] = useState<string | null>(null)
  const conciliar = useConciliar()
  const corrigirConta = useCorrigirConta()
  const contasAtivas = (contas.data ?? []).filter((c) => c.ativo)
  const conta = contasAtivas.find((c) => c.id === contaId) ?? contasAtivas[0] ?? null
  const movs = useMovimentosConta(conta?.id ?? '', mes)
  const dias = useMemo(() => Array.from(new Set((movs.data ?? []).map((m) => m.data))).sort(), [movs.data])
  useEffect(() => { setDia('') }, [mes, conta?.id])

  const { conferidos, pendentes } = useMemo(() => {
    const l = movs.data ?? []
    return {
      conferidos: l.filter((m) => m.conciliado_em),
      pendentes: l.filter((m) => !m.conciliado_em),
    }
  }, [movs.data])
  const soma = (xs: MovConciliacao[]) => xs.reduce((s, m) => s + m.valor, 0)

  const termo = busca.trim().toLowerCase()
  const lista = (movs.data ?? []).filter((m) => {
    if (dia && m.data !== dia) return false
    if (situacao === 'pendente' && m.conciliado_em) return false
    if (situacao === 'conferido' && !m.conciliado_em) return false
    if (sinal === 'entrada' && m.valor < 0) return false
    if (sinal === 'saida' && m.valor >= 0) return false
    if (!termo) return true
    return m.descricao.toLowerCase().includes(termo) || (m.pessoa?.toLowerCase().includes(termo) ?? false) || String(m.valor).includes(termo)
  })
  // o botão "Conferir todos" segue o que está na tela: filtrou, confere só o que aparece
  const pendentesVisiveis = lista.filter((m) => !m.conciliado_em)

  return (
    <>
      <CabecalhoPagina titulo="Conciliação bancária" descricao="Confira os movimentos de cada conta contra o extrato do banco" />
      <div className="mb-3 flex flex-wrap items-start gap-3">
        <SeletorMes mes={mes} aoMudar={setMes} />
        <select aria-label="Conta" value={conta?.id ?? ''} onChange={(e) => setContaId(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
          {contasAtivas.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
        </select>
      </div>
      {conciliar.error != null && <div className="mb-3"><Alerta tipo="erro">{mensagemDeErro(conciliar.error)}</Alerta></div>}
      {corrigirConta.error != null && <div className="mb-3"><Alerta tipo="erro">{mensagemDeErro(corrigirConta.error)}</Alerta></div>}
      {!conta ? <Alerta tipo="info">Cadastre uma conta antes.</Alerta> : movs.isPending ? <Carregando /> : (
        <div className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-3">
            <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">Movimentos no mês</p><p className="mt-1 text-xl font-semibold tabular-nums">{(movs.data ?? []).length}</p></Cartao>
            <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">Conferidos</p><p className="mt-1 text-xl font-semibold tabular-nums text-green-700">{conferidos.length} · {formatarMoeda(soma(conferidos))}</p></Cartao>
            <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">Pendentes de conferência</p><p className={`mt-1 text-xl font-semibold tabular-nums ${pendentes.length > 0 ? 'text-amber-700' : 'text-green-700'}`}>{pendentes.length} · {formatarMoeda(soma(pendentes))}</p></Cartao>
          </div>
          <Cartao className="p-0">
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-6 py-3">
              <h2 className="text-sm font-semibold">{conta.nome} · {mes}</h2>
              <span className="flex gap-2">
                <Botao variante="secundario" disabled={pendentesVisiveis.length === 0} carregando={conciliar.isPending}
                  onClick={() => conciliar.mutate({ ids: pendentesVisiveis.map((m) => m.id), conciliar: true })}>Conferir todos{pendentesVisiveis.length !== pendentes.length ? ` (${pendentesVisiveis.length})` : ''}</Botao>
              </span>
            </div>
            <BarraFiltros>
              <CampoBusca valor={busca} aoMudar={setBusca} rotulo="Buscar por cliente, descrição ou valor" />
              <SelectFiltro valor={dia} aoMudar={setDia} rotulo="Filtrar por dia">
                <option value="">Todos os dias</option>
                {dias.map((d) => <option key={d} value={d}>{formatarData(d)}</option>)}
              </SelectFiltro>
              <SelectFiltro valor={situacao} aoMudar={(v) => setSituacao(v as typeof situacao)} rotulo="Filtrar por situação">
                <option value="">Conferidos e pendentes</option>
                <option value="pendente">Só pendentes</option>
                <option value="conferido">Só conferidos</option>
              </SelectFiltro>
              <SelectFiltro valor={sinal} aoMudar={(v) => setSinal(v as typeof sinal)} rotulo="Filtrar por entrada ou saída">
                <option value="">Entradas e saídas</option>
                <option value="entrada">Só entradas</option>
                <option value="saida">Só saídas</option>
              </SelectFiltro>
              <ContagemFiltro visiveis={lista.length} total={(movs.data ?? []).length} singular="movimento" plural="movimentos" />
            </BarraFiltros>
            {lista.length === 0 ? (
              <p className="px-6 py-10 text-center text-sm text-ink-muted">{(movs.data ?? []).length === 0 ? 'Nenhum movimento nesta conta neste mês.' : 'Nenhum movimento com esses filtros.'}</p>
            ) : (
              <ul className="divide-y divide-line">
                {lista.map((m) => (
                  <li key={m.id} className="flex items-center justify-between gap-3 px-6 py-2.5 text-sm">
                    <label className="flex min-w-0 flex-1 cursor-pointer items-center gap-3">
                      <input type="checkbox" className="size-4 accent-brand-600" checked={Boolean(m.conciliado_em)}
                        onChange={(e) => conciliar.mutate({ ids: [m.id], conciliar: e.target.checked })} />
                      <span className="min-w-0">
                        <span className="font-medium">{m.pessoa ?? m.descricao}</span>
                        {m.pessoa && <span className="ml-2 text-ink-muted">{m.descricao}</span>}
                        <span className="ml-2 text-xs text-ink-muted">{formatarData(m.data)}</span>
                      </span>
                    </label>
                    <span className="flex shrink-0 items-center gap-2">
                      {movendoId === m.id ? (
                        <select aria-label="Mover para outra conta" autoFocus className="h-8 rounded-md border border-line bg-white px-1 text-xs" defaultValue=""
                          disabled={corrigirConta.isPending}
                          onChange={(e) => { if (e.target.value) { corrigirConta.mutate({ lancamentoId: m.lancamento_id, contaId: e.target.value }); setMovendoId(null) } }}
                          onBlur={() => setMovendoId(null)}>
                          <option value="" disabled>Mover pra...</option>
                          {contasAtivas.filter((c) => c.id !== conta.id).map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
                        </select>
                      ) : (
                        <button type="button" onClick={() => setMovendoId(m.id)} className="text-xs text-ink-muted underline hover:text-ink" title="Lançado na conta errada? Corrige sem reabrir o lançamento inteiro.">Ajustar baixa</button>
                      )}
                      <span className={`font-medium tabular-nums ${m.valor < 0 ? 'text-red-700' : 'text-green-700'}`}>{formatarMoeda(m.valor)}</span>
                      {m.conciliado_em ? <Distintivo tom="ok">Conferido</Distintivo> : <Distintivo tom="alerta">Pendente</Distintivo>}
                    </span>
                  </li>
                ))}
              </ul>
            )}
            <p className="border-t border-line px-6 py-2 text-xs text-ink-muted">Marque cada movimento que você encontrou no extrato do banco. Mês 100% conferido + saldo batendo = pode fechar o mês com segurança.</p>
          </Cartao>
        </div>
      )}
    </>
  )
}
