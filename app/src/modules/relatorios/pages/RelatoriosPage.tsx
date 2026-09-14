import { Link } from 'react-router'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { AREAS, RELATORIOS, relatorioPorId } from '../catalogo'
import { useFavoritos, useRemoverFavorito } from '../api'

/** Central de Relatórios: catálogo por área + favoritos do usuário. */
export function RelatoriosPage() {
  const favoritos = useFavoritos()
  const remover = useRemoverFavorito()
  return (
    <>
      <CabecalhoPagina titulo="Relatórios" descricao="Um lugar só para tirar, filtrar, exportar e imprimir os relatórios do sistema" />
      <div className="space-y-6">
        {(favoritos.data?.length ?? 0) > 0 && (
          <Cartao>
            <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-ink-muted">Meus favoritos</h2>
            <ul className="divide-y divide-line text-sm">
              {favoritos.data!.map((f) => {
                const r = relatorioPorId(f.relatorio)
                return (
                  <li key={f.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                    <Link to={`/relatorios/${f.relatorio}?f=${f.id}`} className="font-medium text-brand-700 hover:underline">{f.nome}</Link>
                    <span className="text-xs text-ink-muted">{r?.titulo ?? f.relatorio}</span>
                    <Botao variante="secundario" className="h-8 px-2 text-xs" onClick={() => remover.mutate(f.id)} carregando={remover.isPending}>Remover</Botao>
                  </li>
                )
              })}
            </ul>
          </Cartao>
        )}
        {AREAS.map((area) => {
          const lista = RELATORIOS.filter((r) => r.area === area)
          return (
            <Cartao key={area}>
              <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-ink-muted">{area}</h2>
              {lista.length === 0 ? (
                <p className="text-sm text-ink-muted">Em breve — os relatórios desta área entram junto com as próximas etapas.</p>
              ) : (
                <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                  {lista.map((r) => (
                    <li key={r.id}>
                      <Link to={`/relatorios/${r.id}`} className="block h-full rounded-md border border-line p-3 transition hover:border-brand-600 hover:bg-brand-50">
                        <p className="font-medium">{r.titulo}</p>
                        <p className="mt-1 text-xs text-ink-muted">{r.descricao}</p>
                      </Link>
                    </li>
                  ))}
                </ul>
              )}
            </Cartao>
          )
        })}
      </div>
    </>
  )
}
