import { useId, type TextareaHTMLAttributes } from 'react'

interface Props extends TextareaHTMLAttributes<HTMLTextAreaElement> { rotulo: string }

export function AreaTexto({ rotulo, className = '', id, ...rest }: Props) {
  const gerado = useId()
  const areaId = id ?? gerado
  return (
    <div className="space-y-1">
      <label htmlFor={areaId} className="block text-sm font-medium text-ink">{rotulo}</label>
      <textarea id={areaId} {...rest} className={`w-full rounded-md border border-line bg-white px-3 py-2 text-sm outline-none transition focus:border-brand-600 focus:ring-2 focus:ring-brand-100 ${className}`} />
    </div>
  )
}
