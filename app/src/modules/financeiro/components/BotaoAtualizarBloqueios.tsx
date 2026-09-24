import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { supabase } from '../../../core/supabase/client'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { useNegocios } from '../../negocios/api'
import { useConfigsNotificacao } from '../../notificacoes/api'

interface Props {
  /** mesmo valor do filtro de negócio da tela: '' = todos, 'pessoal' ou o id de um negócio. */
  filtroNegocio?: string
}

/**
 * Roda agora a checagem de bloqueio/desbloqueio automático (mesma lógica do robô das 00:00),
 * para os negócios com o toggle ligado — sem esperar virar o dia. Some sozinho se nenhum
 * negócio (dentro do filtro atual da tela) tiver bloqueio automático ligado.
 */
export function BotaoAtualizarBloqueios({ filtroNegocio }: Props) {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  const negocios = useNegocios()
  const configs = useConfigsNotificacao()
  const [resultado, setResultado] = useState<number | null>(null)
  const elegiveis = (negocios.data ?? [])
    .filter((n) => n.ativo && (configs.data ?? []).some((c) => c.negocio_id === n.id && c.bloqueio_automatico))
    .filter((n) => !filtroNegocio || n.id === filtroNegocio)

  const rodar = useMutation({
    mutationFn: async () => {
      let total = 0
      for (const n of elegiveis) {
        const { data, error } = await supabase.rpc('executar_bloqueios_agora', { p_negocio_id: n.id })
        if (error) throw error
        total += (data as { executados: number } | null)?.executados ?? 0
      }
      return total
    },
    onSuccess: (total) => {
      setResultado(total)
      void qc.invalidateQueries({ queryKey: ['cobranca', organizacao.id] })
      void qc.invalidateQueries({ queryKey: ['contratos', organizacao.id] })
      void qc.invalidateQueries({ queryKey: ['lancamentos', organizacao.id] })
    },
  })

  if (elegiveis.length === 0) return null
  return (
    <div className="mb-4 space-y-2">
      <Botao variante="secundario" onClick={() => { setResultado(null); rodar.mutate() }} carregando={rodar.isPending}>
        Atualizar bloqueio/desbloqueio agora
      </Botao>
      {rodar.error != null && <Alerta tipo="erro">{mensagemDeErro(rodar.error)}</Alerta>}
      {resultado !== null && <Alerta tipo="sucesso">{resultado ? `${resultado} contrato(s) atualizado(s) agora.` : 'Nada para atualizar agora — está tudo em dia.'}</Alerta>}
    </div>
  )
}
