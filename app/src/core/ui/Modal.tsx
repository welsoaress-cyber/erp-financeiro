import { useEffect, type ReactNode } from 'react'

interface Props {
  titulo: string
  aberto: boolean
  aoFechar: () => void
  children: ReactNode
}

export function Modal({ titulo, aberto, aoFechar, children }: Props) {
  useEffect(() => {
    if (!aberto) return
    const aoTeclar = (e: KeyboardEvent) => { if (e.key === 'Escape') aoFechar() }
    window.addEventListener('keydown', aoTeclar)
    return () => window.removeEventListener('keydown', aoTeclar)
  }, [aberto, aoFechar])

  if (!aberto) return null
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4" role="dialog" aria-modal="true" aria-labelledby="modal-titulo">
      <button type="button" aria-label="Fechar" className="absolute inset-0 bg-black/40" onClick={aoFechar} />
      <div className="relative w-full max-w-md rounded-lg border border-line bg-white p-6 shadow-xl">
        <h2 id="modal-titulo" className="mb-4 text-lg font-semibold">{titulo}</h2>
        {children}
      </div>
    </div>
  )
}
