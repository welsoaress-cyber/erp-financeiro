export function Carregando({ texto = 'Carregando…', telaCheia = false }: { texto?: string; telaCheia?: boolean }) {
  const conteudo = (
    <div className="flex items-center gap-3 text-sm text-ink-muted">
      <span className="size-5 animate-spin rounded-full border-2 border-brand-600 border-t-transparent" />
      {texto}
    </div>
  )
  if (!telaCheia) return <div className="p-6">{conteudo}</div>
  return <div className="flex h-full min-h-screen items-center justify-center">{conteudo}</div>
}
