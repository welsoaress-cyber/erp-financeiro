import type { ReactNode } from 'react'

interface Props {
  tipo?: 'erro' | 'sucesso' | 'info'
  titulo?: string
  children?: ReactNode
}

const estilos = {
  erro: 'border-red-200 bg-red-50 text-red-800',
  sucesso: 'border-green-200 bg-green-50 text-green-800',
  info: 'border-brand-100 bg-brand-50 text-brand-900',
}

export function Alerta({ tipo = 'info', titulo, children }: Props) {
  return (
    <div role={tipo === 'erro' ? 'alert' : 'status'} className={`rounded-md border px-4 py-3 text-sm ${estilos[tipo]}`}>
      {titulo && <p className="font-semibold">{titulo}</p>}
      {children && <div className={titulo ? 'mt-1' : ''}>{children}</div>}
    </div>
  )
}
