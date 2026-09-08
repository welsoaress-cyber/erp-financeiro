import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { Conta, DadosConta } from './tipos'

const chave = (organizacaoId: string) => ['contas', organizacaoId] as const

export function useContas() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chave(organizacao.id),
    queryFn: async (): Promise<Conta[]> => {
      const { data, error } = await supabase
        .from('vw_saldo_contas')
        .select('*')
        .eq('organizacao_id', organizacao.id)
        .order('ativo', { ascending: false })
        .order('nome')
      if (error) throw error
      return data ?? []
    },
  })
}

export function useCriarConta() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (dados: DadosConta) => {
      const { data, error } = await supabase
        .from('contas')
        .insert({ ...dados, nome: dados.nome.trim(), organizacao_id: organizacao.id })
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['contas', organizacao.id] }),
  })
}

/** Ajuste de saldo: lançamento efetivado da diferença (o saldo é derivado dos movimentos, nunca gravado). */
export function useAjustarSaldo() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ contaId, diferenca }: { contaId: string; diferenca: number }) => {
      const tipo = diferenca > 0 ? 'receita' : 'despesa'
      let { data: cat } = await supabase.from('categorias').select('id').eq('organizacao_id', organizacao.id).eq('nome', 'Ajuste de saldo').eq('tipo', tipo).maybeSingle()
      if (!cat) {
        const { data: nova, error: e1 } = await supabase.from('categorias').insert({ organizacao_id: organizacao.id, nome: 'Ajuste de saldo', tipo, ativo: true }).select('id').single()
        if (e1) throw e1
        cat = nova
      }
      const hoje = new Date().toISOString().slice(0, 10)
      const { data, error } = await supabase.rpc('criar_lancamento', {
        p_tipo: tipo,
        p_descricao: 'Ajuste de saldo',
        p_valor: Math.round(Math.abs(diferenca) * 100) / 100,
        p_data_competencia: hoje,
        p_data_vencimento: hoje,
        p_data_efetivacao: hoje,
        p_conta_id: contaId,
        p_categoria_id: cat.id,
        p_observacao: 'Ajuste manual para igualar o saldo real da conta.',
      })
      if (error) throw error
      return data
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: chave(organizacao.id) })
      void qc.invalidateQueries({ queryKey: ['lancamentos', organizacao.id] })
      void qc.invalidateQueries({ queryKey: ['categorias', organizacao.id] })
    },
  })
}

export function useAtualizarConta() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    // tipo nunca é enviado: o banco também rejeita, mas a UI não tenta.
    mutationFn: async ({ id, ...dados }: Omit<DadosConta, 'tipo'> & { id: string }) => {
      const { data, error } = await supabase
        .from('contas')
        .update({ ...dados, nome: dados.nome.trim() })
        .eq('id', id)
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: chave(organizacao.id) }),
  })
}
