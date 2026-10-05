import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { BoletoPendente } from './tipos'

const chave = (org: string) => ['boletos-pendentes', org] as const

/** Boletos pendentes de envio (0126): boleto, ativo, previsto, nunca registrado como enviado. */
export function useBoletosPendentes() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chave(organizacao.id),
    queryFn: async (): Promise<BoletoPendente[]> => {
      const { data, error } = await supabase
        .from('vw_rel_boletos_pendentes')
        .select('*')
        .eq('organizacao_id', organizacao.id)
        .order('data_vencimento', { ascending: true })
      if (error) throw error
      return (data ?? []).map((b) => ({ ...b, valor: Number(b.valor), valor_desconto: Number(b.valor_desconto) })) as BoletoPendente[]
    },
  })
}

export function useRegistrarBoletoEnviado() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ lancamento_id, mensagem }: { lancamento_id: string; mensagem: string }) => {
      const { data, error } = await supabase.rpc('registrar_boleto_enviado', { p_lancamento_id: lancamento_id, p_mensagem: mensagem })
      if (error) throw error
      return data
    },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: chave(organizacao.id) }) },
  })
}
