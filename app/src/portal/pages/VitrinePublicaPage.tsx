import { useParams } from 'react-router'
import { Carregando } from '../../core/ui/Carregando'
import { useVitrinePublica } from '../api'

/** Vitrine pública dos prêmios do Indique e Ganhe (sem login) — peça de divulgação. */
export function VitrinePublicaPage() {
  const { slug = '' } = useParams()
  const vitrine = useVitrinePublica(slug)
  if (vitrine.isPending) return <div className="p-10"><Carregando /></div>
  const v = vitrine.data
  if (!v) return <p className="p-10 text-center text-sm text-ink-muted">Vitrine não encontrada.</p>
  const porFaixa = (f: number) => v.premios.filter((p) => p.faixa === f)
  return (
    <div className="mx-auto max-w-5xl space-y-6 px-4 py-8">
      <header className="text-center">
        {v.logo && <img src={v.logo} alt={v.negocio} className="mx-auto mb-3 h-14 object-contain" />}
        <h1 className="text-2xl font-bold" style={{ color: v.cor }}>🎁 Indique e Ganhe · {v.negocio}</h1>
        <p className="mt-1 text-sm text-ink-muted">Indique um amigo. Quando ele instalar, você escolhe um presente — entrega na sua casa em até 10 dias úteis.</p>
        <p className="mx-auto mt-2 max-w-xl rounded-md bg-surface px-3 py-2 text-sm font-medium">🎯 A regra é simples: <b>quanto maior o plano que o seu indicado fechar, melhor a vitrine</b> de presentes que abre para você. Uma escolha por indicação instalada — indicou 3, ganhou 3.</p>
        {v.texto && <p className="mt-2 text-sm">{v.texto}</p>}
      </header>
      {v.faixas.length === 0 && v.premios.length === 0 && <p className="text-center text-sm text-ink-muted">Os prêmios serão divulgados em breve.</p>}
      {(v.faixas.length > 0 ? v.faixas : [...new Set(v.premios.map((p) => p.faixa))].sort().map((f) => ({ faixa: f, nome: `Faixa ${f}`, teto: 0 }))).map((f) => (
        <section key={f.faixa}>
          <div className="mb-3 rounded-lg px-4 py-3 text-white" style={{ backgroundColor: v.cor }}>
            <p className="text-lg font-bold uppercase tracking-wide">📶 Plano {f.nome}</p>
            <p className="mt-0.5 text-sm opacity-90">Seu indicado instalou <b>este plano</b>? Você escolhe <b>1 presente</b> desta vitrine.</p>
          </div>
          {porFaixa(f.faixa).length === 0 ? <p className="text-xs text-ink-muted">Prêmios desta faixa em breve.</p> : (
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
              {porFaixa(f.faixa).map((p, i) => (
                <div key={i} className="overflow-hidden rounded-lg border border-line">
                  {p.foto
                    ? <img src={p.foto} alt={p.nome} className="aspect-square w-full object-cover" />
                    : <div className="flex aspect-square w-full items-center justify-center bg-surface text-5xl">🎁</div>}
                  <p className="px-2 py-2 text-center text-sm font-medium">{p.nome}</p>
                </div>
              ))}
            </div>
          )}
        </section>
      ))}
      <footer className="pt-2 text-center text-xs text-ink-muted">A faixa do presente depende do plano que o seu indicado fechar. Peça o seu link de indicação no portal do cliente.</footer>
    </div>
  )
}
