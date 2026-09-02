type Tom = 'ok' | 'neutro' | 'alerta' | 'info'

const estilos: Record<Tom, string> = {
  ok: 'bg-green-50 text-green-700 ring-green-200',
  neutro: 'bg-surface text-ink-muted ring-line',
  alerta: 'bg-amber-50 text-amber-800 ring-amber-200',
  info: 'bg-brand-50 text-brand-700 ring-brand-100',
}

export function Distintivo({ tom, children }: { tom: Tom; children: string }) {
  return <span className={`inline-flex whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-medium ring-1 ${estilos[tom]}`}>{children}</span>
}
