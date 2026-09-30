import { Cartao } from '../../core/ui/Cartao'
import { Distintivo } from '../../core/ui/Distintivo'
import { Titulo } from './comum'

/** Teaser do futuro serviço de câmera com gravação de 30 dias — ainda em teste técnico, sem contratação disponível. */
export function PortalGravacoesPage() {
  return (
    <div className="space-y-4">
      <Titulo>Minhas gravações</Titulo>
      <Cartao className="overflow-hidden p-0">
        <div className="bg-gradient-to-br from-brand-700 to-brand-900 px-6 py-8 text-center text-white">
          <p className="text-3xl">🎥</p>
          <p className="mt-2 text-lg font-semibold">Câmera de segurança com 30 dias de gravação</p>
          <p className="mx-auto mt-1 max-w-sm text-sm text-white/85">Alugue uma câmera e veja os últimos 30 dias de movimento direto por aqui, sem precisar de cartão de memória.</p>
          <div className="mt-4"><Distintivo tom="info">Em breve</Distintivo></div>
        </div>
        <p className="px-6 py-4 text-center text-sm text-ink-muted">Ainda não disponível pra contratação — assim que lançarmos, você será avisado.</p>
      </Cartao>
    </div>
  )
}
