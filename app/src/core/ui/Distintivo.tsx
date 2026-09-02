export function Distintivo({ tom, children }: { tom: 'ok' | 'neutro'; children: string }) {
  const estilo = tom === 'ok' ? 'bg-green-50 text-green-700 ring-green-200' : 'bg-surface text-ink-muted ring-line'
  return <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ring-1 ${estilo}`}>{children}</span>
}
