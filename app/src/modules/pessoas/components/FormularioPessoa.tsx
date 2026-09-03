import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { documentoValido, formatarDocumento, formatarTelefone, somenteDigitos, TIPOS_PESSOA, type DadosPessoa, type Pessoa, type TipoPessoa } from '../tipos'

interface Props {
  pessoa?: Pessoa
  salvando: boolean
  erro: string | null
  aoSalvar: (dados: DadosPessoa) => void
  aoCancelar: () => void
}

export function FormularioPessoa({ pessoa, salvando, erro, aoSalvar, aoCancelar }: Props) {
  const editando = Boolean(pessoa)
  const [tipo, setTipo] = useState<TipoPessoa>(pessoa?.tipo ?? 'fisica')
  const [nome, setNome] = useState(pessoa?.nome ?? '')
  const [documento, setDocumento] = useState(pessoa?.documento ? formatarDocumento(pessoa.documento) : '')
  const [email, setEmail] = useState(pessoa?.email ?? '')
  const [telefone, setTelefone] = useState(pessoa?.telefone ? formatarTelefone(pessoa.telefone) : '')
  const [observacao, setObservacao] = useState(pessoa?.observacao ?? '')
  const [ativo, setAtivo] = useState(pessoa?.ativo ?? true)
  const [receberAvisos, setReceberAvisos] = useState(pessoa?.receber_avisos ?? true)
  const [erros, setErros] = useState<{ nome?: string; documento?: string; email?: string; telefone?: string }>({})

  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const novos: typeof erros = {}
    const doc = somenteDigitos(documento)
    const tel = somenteDigitos(telefone)
    if (nome.trim().length < 2) novos.nome = 'Informe o nome (mínimo 2 caracteres).'
    if (doc) {
      if (tipo === 'fisica' && doc.length !== 11) novos.documento = 'CPF deve ter 11 dígitos.'
      else if (tipo === 'juridica' && doc.length !== 14) novos.documento = 'CNPJ deve ter 14 dígitos.'
      else if (!documentoValido(doc)) novos.documento = tipo === 'fisica' ? 'CPF inválido.' : 'CNPJ inválido.'
    }
    if (email.trim() && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) novos.email = 'E-mail inválido.'
    if (tel && (tel.length < 10 || tel.length > 13)) novos.telefone = 'Telefone com DDD, 10 ou 11 dígitos.'
    setErros(novos)
    if (Object.keys(novos).length > 0) return
    aoSalvar({ tipo, nome: nome.trim(), documento: doc || null, email: email.trim().toLowerCase() || null, telefone: tel || null, observacao: observacao.trim() || null, ativo, receber_avisos: receberAvisos })
  }

  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <div role="radiogroup" aria-label="Tipo de pessoa" className="grid grid-cols-2 gap-1 rounded-md border border-line p-1">
        {TIPOS_PESSOA.map((t) => (
          <button key={t.valor} type="button" role="radio" aria-checked={tipo === t.valor} onClick={() => setTipo(t.valor)}
            className={`rounded px-2 py-1.5 text-sm ${tipo === t.valor ? 'bg-brand-600 text-white' : 'text-ink-muted hover:text-ink'}`}>{t.rotulo}</button>
        ))}
      </div>
      <Campo rotulo={tipo === 'fisica' ? 'Nome completo' : 'Razão social / nome'} value={nome} onChange={(e) => setNome(e.target.value)} erro={erros.nome} autoFocus maxLength={120} />
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo={tipo === 'fisica' ? 'CPF' : 'CNPJ'} value={documento} inputMode="numeric" onChange={(e) => setDocumento(e.target.value)} onBlur={() => setDocumento(formatarDocumento(somenteDigitos(documento) || null) === '—' ? '' : formatarDocumento(somenteDigitos(documento)))} erro={erros.documento} placeholder={tipo === 'fisica' ? '000.000.000-00' : '00.000.000/0000-00'} />
        <Campo rotulo="Telefone" value={telefone} inputMode="tel" onChange={(e) => setTelefone(e.target.value)} onBlur={() => setTelefone(formatarTelefone(somenteDigitos(telefone) || null))} erro={erros.telefone} placeholder="(11) 99999-9999" />
      </div>
      <Campo rotulo="E-mail" type="email" value={email} onChange={(e) => setEmail(e.target.value)} erro={erros.email} />
      <AreaTexto rotulo="Observação (opcional)" rows={2} maxLength={500} value={observacao} onChange={(e) => setObservacao(e.target.value)} />
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" checked={receberAvisos} onChange={(e) => setReceberAvisos(e.target.checked)} className="size-4 accent-brand-600" />
        Recebe avisos de cobrança por WhatsApp
      </label>
      {editando && (
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />
          Pessoa ativa
        </label>
      )}
      <div className="flex justify-end gap-2 pt-2">
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando}>Voltar</Botao>
        <Botao type="submit" carregando={salvando}>{editando ? 'Salvar alterações' : 'Criar pessoa'}</Botao>
      </div>
    </form>
  )
}
