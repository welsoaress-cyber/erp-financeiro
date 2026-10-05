import { useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'

/** Checa duplicidade antes de começar o trabalho pesado do assistente (a função do banco é a garantia real). */
export async function buscarNotaFiscalImportada(chave: string): Promise<{ criado_em: string } | null> {
  const { data, error } = await supabase.from('notas_fiscais_importadas').select('criado_em').eq('chave', chave).maybeSingle()
  if (error) throw error
  return data
}

/** Trava a chave por último, só depois que a compra/baixa real já foi criada. */
export function useRegistrarNotaFiscalImportada() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (d: {
      negocio_id: string; fornecedor_id: string; chave: string; numero: string | null; valor: number; emitida_em: string | null
      destino: 'compra' | 'contrato'; compra_id?: string | null; contrato_id?: string | null; lancamento_id?: string | null
    }) => {
      const { data, error } = await supabase.rpc('registrar_nota_fiscal_importada', {
        p_negocio_id: d.negocio_id, p_fornecedor_id: d.fornecedor_id, p_chave: d.chave, p_numero: d.numero,
        p_valor: d.valor, p_emitida_em: d.emitida_em, p_destino: d.destino,
        p_compra_id: d.compra_id ?? null, p_contrato_id: d.contrato_id ?? null, p_lancamento_id: d.lancamento_id ?? null,
      })
      if (error) throw error
      return data
    },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['notas-fiscais'] }) },
  })
}
