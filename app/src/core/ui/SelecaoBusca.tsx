import { useEffect, useId, useRef, useState } from 'react'

interface Props {
  rotulo: string
  opcoes: ReadonlyArray<{ valor: string; rotulo: string }>
  value: string
  onChange: (valor: string) => void
  placeholder?: string
  ajuda?: string
  erro?: string
  disabled?: boolean
}

const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

/** Campo tipo "select" com busca: digita e filtra as opções por nome, em vez de rolar uma lista longa. */
export function SelecaoBusca({ rotulo, opcoes, value, onChange, placeholder, ajuda, erro, disabled }: Props) {
  const campoId = useId()
  const selecionada = opcoes.find((o) => o.valor === value)
  const [texto, setTexto] = useState(selecionada?.rotulo ?? '')
  const [aberto, setAberto] = useState(false)
  const fecharRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => { setTexto(selecionada?.rotulo ?? '') }, [selecionada?.rotulo])

  const busca = normalizar(texto)
  const filtradas = !aberto ? [] : busca && texto !== selecionada?.rotulo ? opcoes.filter((o) => normalizar(o.rotulo).includes(busca)) : opcoes

  function escolher(o: { valor: string; rotulo: string }) {
    onChange(o.valor)
    setTexto(o.rotulo)
    setAberto(false)
  }

  return (
    <div className="relative space-y-1">
      <label htmlFor={campoId} className="block text-sm font-medium text-ink">{rotulo}</label>
      <input
        id={campoId}
        type="text"
        autoComplete="off"
        disabled={disabled}
        value={texto}
        placeholder={placeholder}
        onFocus={() => setAberto(true)}
        onChange={(e) => { setTexto(e.target.value); setAberto(true); if (value) onChange('') }}
        onBlur={() => { fecharRef.current = setTimeout(() => setAberto(false), 150) }}
        className={`h-10 w-full rounded-md border bg-white px-3 text-sm outline-none transition focus:border-brand-600 focus:ring-2 focus:ring-brand-100 disabled:cursor-not-allowed disabled:bg-surface disabled:text-ink-muted ${erro ? 'border-red-500' : 'border-line'}`}
      />
      {aberto && filtradas.length > 0 && (
        <ul className="absolute z-10 mt-1 max-h-56 w-full overflow-auto rounded-md border border-line bg-white py-1 shadow-lg">
          {filtradas.map((o) => (
            <li key={o.valor}>
              <button type="button" onMouseDown={(e) => { e.preventDefault(); if (fecharRef.current) clearTimeout(fecharRef.current); escolher(o) }}
                className="block w-full px-3 py-1.5 text-left text-sm hover:bg-surface">{o.rotulo}</button>
            </li>
          ))}
        </ul>
      )}
      {aberto && busca && filtradas.length === 0 && <p className="absolute z-10 mt-1 w-full rounded-md border border-line bg-white px-3 py-1.5 text-sm text-ink-muted shadow-lg">Nada encontrado.</p>}
      {erro && <p className="text-xs text-red-600">{erro}</p>}
      {ajuda && <p className="text-xs text-ink-muted">{ajuda}</p>}
    </div>
  )
}
