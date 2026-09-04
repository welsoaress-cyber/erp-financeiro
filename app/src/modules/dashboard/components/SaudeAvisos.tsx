import { Link } from 'react-router'
import { Cartao } from '../../../core/ui/Cartao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { formatarData } from '../../../core/formatos'
import type { Negocio } from '../../negocios/tipos'
import type { SaudeNotificacoes } from '../api'

interface Props {
  negocios: Negocio[]
  saude: SaudeNotificacoes | undefined
}

/** Situação dos avisos de WhatsApp por negócio: configurado, com erro, com pendência antiga ou sem configuração. */
export function SaudeAvisos({ negocios, saude }: Props) {
  const ativos = negocios.filter((n) => n.ativo)
  if (!saude || ativos.length === 0) return null

  const porNegocio = ativos.map((n) => {
    const cfg = saude.configs.find((c) => c.negocio_id === n.id)
    const log = saude.log.filter((l) => l.negocio_id === n.id)
    const erros24h = log.filter((l) => l.status === 'erro' && Date.now() - new Date(l.criado_em).getTime() < 86_400_000).length
    const pendentesAntigos = log.filter((l) => l.status === 'pendente' && Date.now() - new Date(l.criado_em).getTime() > 86_400_000).length
    const ultimoEnvio = log.filter((l) => l.data_envio).map((l) => l.data_envio!).sort().at(-1) ?? null
    const situacao = !cfg || !cfg.ativo
      ? { tom: 'alerta' as const, rotulo: 'Sem configuração', acao: 'Configurar' }
      : erros24h > 0
        ? { tom: 'alerta' as const, rotulo: `${erros24h} erro(s) nas últimas 24h`, acao: 'Verificar' }
        : pendentesAntigos > 0
          ? { tom: 'alerta' as const, rotulo: `${pendentesAntigos} pendente(s) há mais de 1 dia`, acao: 'Enviar pendentes' }
          : { tom: 'ok' as const, rotulo: 'Em dia', acao: null }
    return { negocio: n, situacao, ultimoEnvio }
  })

  const comAcao = porNegocio.filter((x) => x.situacao.acao !== null).length

  return (
    <Cartao className="p-0">
      <div className="flex items-center justify-between border-b border-line px-6 py-3">
        <h2 className="text-sm font-semibold">Avisos no WhatsApp {comAcao > 0 ? <Distintivo tom="alerta">{`${comAcao} ação(ões) necessária(s)`}</Distintivo> : <Distintivo tom="ok">Tudo certo</Distintivo>}</h2>
        <Link to="/notificacoes" className="text-xs font-medium text-brand-600 hover:underline">Abrir notificações</Link>
      </div>
      <ul className="divide-y divide-line">
        {porNegocio.map(({ negocio, situacao, ultimoEnvio }) => (
          <li key={negocio.id} className="flex items-center justify-between gap-3 px-6 py-3 text-sm">
            <span className="min-w-0">
              <span className="font-medium">{negocio.nome}</span>
              {ultimoEnvio && <span className="ml-2 text-xs text-ink-muted">último envio {formatarData(ultimoEnvio.slice(0, 10))}</span>}
            </span>
            <span className="flex shrink-0 items-center gap-2">
              <Distintivo tom={situacao.tom}>{situacao.rotulo}</Distintivo>
              {situacao.acao && <Link to="/notificacoes" className="text-xs font-medium text-brand-600 hover:underline">{situacao.acao}</Link>}
            </span>
          </li>
        ))}
      </ul>
    </Cartao>
  )
}
