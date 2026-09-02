import { useId, type InputHTMLAttributes } from 'react'

interface Props extends InputHTMLAttributes<HTMLInputElement> {
  rotulo: string
  erro?: string
}

export function Campo({ rotulo, erro, className = '', id, ...rest }: Props) {
  const gerado = useId()
  const inputId = id ?? gerado
  return (
    <div className="space-y-1">
      <label htmlFor={inputId} className="block text-sm font-medium text-ink">{rotulo}</label>
      <input
        id={inputId}
        {...rest}
        aria-invalid={erro ? true : undefined}
        className={`h-10 w-full rounded-md border bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-2 focus:ring-brand-100 ${erro ? 'border-red-500' : 'border-line'} ${className}`}
      />
      {erro && <p className="text-xs text-red-600">{erro}</p>}
    </div>
  )
}
