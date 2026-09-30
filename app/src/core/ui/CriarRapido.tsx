import { useState } from 'react'
import { Botao } from './Botao'
import { mensagemDeErro } from '../erros/mensagemDeErro'

/** Cadastro rápido sem sair do formulário: "+ Criar…" abre um campo de nome e cria na hora. */
export function CriarRapido({ rotulo, aoCriar }: { rotulo: string; aoCriar: (nome: string) => Promise<void> }) {
  const [aberto, setAberto] = useState(false)
  const [nome, setNome] = useState('')
  const [criando, setCriando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  if (!aberto) {
    return <button type="button" className="block text-xs font-medium text-brand-600 hover:underline" onClick={() => setAberto(true)}>+ {rotulo}</button>
  }
  async function confirmar() {
    if (nome.trim().length < 2 || criando) return
    setCriando(true); setErro(null)
    try {
      await aoCriar(nome.trim())
      setNome(''); setAberto(false)
    } catch (e) {
      setErro(mensagemDeErro(e))
    } finally {
      setCriando(false)
    }
  }
  return (
    <div className="space-y-1 rounded-md border border-line bg-surface/60 p-2">
      <div className="flex items-center gap-2">
        <input
          value={nome}
          onChange={(e) => setNome(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); void confirmar() } }}
          placeholder="Nome"
          autoFocus
          className="h-8 flex-1 rounded-md border border-line bg-white px-2 text-sm outline-none focus:border-brand-600"
        />
        <Botao type="button" onClick={() => void confirmar()} carregando={criando} disabled={nome.trim().length < 2}>Criar</Botao>
        <Botao type="button" variante="secundario" onClick={() => { setAberto(false); setErro(null) }}>×</Botao>
      </div>
      {erro && <p className="text-xs text-red-600">{erro}</p>}
    </div>
  )
}
