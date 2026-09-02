import { CabecalhoPagina } from './CabecalhoPagina'
import { Cartao } from './Cartao'

/** Placeholder padrão para módulos ainda não implementados. Sem lógica financeira. */
export function ModuloEmBreve({ titulo, descricao, etapa }: { titulo: string; descricao: string; etapa: string }) {
  return (
    <>
      <CabecalhoPagina titulo={titulo} descricao={descricao} />
      <Cartao className="flex flex-col items-center gap-2 py-16 text-center">
        <p className="text-sm font-medium">Módulo ainda não disponível</p>
        <p className="text-sm text-ink-muted">Previsto para a {etapa}.</p>
      </Cartao>
    </>
  )
}
