import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { SeletorMes } from '../../../core/ui/SeletorMes'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../../core/formatos'
import { supabase } from '../../../core/supabase/client'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { usePeriodo } from '../../../core/periodo/usePeriodo'
import { useContas } from '../../contas/api'

interface MovConciliacao { id: string; lancamento_id: string; valor: number; data: string; conciliado_em: string | null; descricao: string }

function useMovimentosConta(contaId: string, mes: string) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: ['conciliacao', organizacao.id, contaId, mes],
    enabled: Boolean(contaId),
    queryFn: async (): Promise<MovConciliacao[]> => {
      const inicio = `${mes}-01`
      const fim = new Date(Number(mes.slice(0, 4)), Number(mes.slice(5, 7)), 0).toISOString().slice(0, 10)
      const { data, error } = await supabase
        .from('movimentos')
        .select('id, lancamento_id, valor, data, conciliado_em, lancamentos(descricao)')
        .eq('organizacao_id', organizacao.id)
        .eq('conta_id', contaId)
        .gte('data', inicio)
        .lte('data', fim)
        .order('data')
      if (error) throw error
      return (data ?? []).map((m) => ({
        id: m.id, lancamento_id: m.lancamento_id, valor: Number(m.valor), data: m.data, conciliado_em: m.conciliado_em,
        descricao: (m.lancamentos as unknown as { descricao: string } | null)?.descricao ?? '—',
      }))
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

/** Conciliação bancária: conferir os movimentos de cada conta contra o extrato, mês a mês. */
export function ConciliacaoPage() {
  const { mes, setMes } = usePeriodo()
  const contas = useContas()
  const [contaId, setContaId] = useState('')
  const conciliar = useConciliar()
  const contasAtivas = (contas.data ?? []).filter((c) => c.ativo)
  const conta = contasAtivas.find((c) => c.id === contaId) ?? contasAtivas[0] ?? null
  const movs = useMovimentosConta(conta?.id ?? '', mes)

  const { conferidos, pendentes } = useMemo(() => {
    const l = movs.data ?? []
    return {
      conferidos: l.filter((m) => m.conciliado_em),
      pendentes: l.filter((m) => !m.conciliado_em),
    }
  }, [movs.data])
  const soma = (xs: MovConciliacao[]) => xs.reduce((s, m) => s + m.valor, 0)

  return (
    <>
      <CabecalhoPagina titulo="Conciliação bancária" descricao="Confira os movimentos de cada conta contra o extrato do banco" />
      <div className="mb-3 flex flex-wrap items-center gap-3">
        <SeletorMes mes={mes} aoMudar={setMes} />
        <select aria-label="Conta" value={conta?.id ?? ''} onChange={(e) => setContaId(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
          {contasAtivas.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
        </select>
      </div>
      {conciliar.error != null && <div className="mb-3"><Alerta tipo="erro">{mensagemDeErro(conciliar.error)}</Alerta></div>}
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
                <Botao variante="secundario" disabled={pendentes.length === 0} carregando={conciliar.isPending}
                  onClick={() => conciliar.mutate({ ids: pendentes.map((m) => m.id), conciliar: true })}>Conferir todos</Botao>
              </span>
            </div>
            {(movs.data ?? []).length === 0 ? (
              <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhum movimento nesta conta neste mês.</p>
            ) : (
              <ul className="divide-y divide-line">
                {(movs.data ?? []).map((m) => (
                  <li key={m.id} className="flex items-center justify-between gap-3 px-6 py-2.5 text-sm">
                    <label className="flex min-w-0 flex-1 cursor-pointer items-center gap-3">
                      <input type="checkbox" className="size-4 accent-brand-600" checked={Boolean(m.conciliado_em)}
                        onChange={(e) => conciliar.mutate({ ids: [m.id], conciliar: e.target.checked })} />
                      <span className="min-w-0">
                        <span className="font-medium">{m.descricao}</span>
                        <span className="ml-2 text-xs text-ink-muted">{formatarData(m.data)}</span>
                      </span>
                    </label>
                    <span className="flex shrink-0 items-center gap-2">
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
