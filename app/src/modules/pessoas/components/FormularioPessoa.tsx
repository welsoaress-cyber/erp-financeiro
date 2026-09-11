import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { documentoValido, formatarDocumento, formatarTelefone, normalizarTelefone, somenteDigitos, telefoneValido, TIPOS_PESSOA, type DadosPessoa, type Pessoa, type TipoPessoa } from '../tipos'

interface Props {
  pessoa?: Pessoa
  salvando: boolean
  excluindo?: boolean
  erro: string | null
  aoSalvar: (dados: DadosPessoa) => void
  aoCancelar: () => void
  aoExcluir?: () => void
}

export function FormularioPessoa({ pessoa, salvando, excluindo, erro, aoSalvar, aoCancelar, aoExcluir }: Props) {
  const editando = Boolean(pessoa)
  const [tipo, setTipo] = useState<TipoPessoa>(pessoa?.tipo ?? 'fisica')
  const [nome, setNome] = useState(pessoa?.nome ?? '')
  const [documento, setDocumento] = useState(pessoa?.documento ? formatarDocumento(pessoa.documento) : '')
  const [email, setEmail] = useState(pessoa?.email ?? '')
  const [telefone, setTelefone] = useState(pessoa?.telefone ? formatarTelefone(pessoa.telefone) : '')
  const [loginServidor, setLoginServidor] = useState(pessoa?.login_servidor ?? '')
  const [endereco, setEndereco] = useState(pessoa?.endereco ?? '')
  const [nascimento, setNascimento] = useState(pessoa?.data_nascimento ?? '')
  const [observacao, setObservacao] = useState(pessoa?.observacao ?? '')
  const [ativo, setAtivo] = useState(pessoa?.ativo ?? true)
  const [receberAvisos, setReceberAvisos] = useState(pessoa?.receber_avisos ?? true)
  const [erros, setErros] = useState<{ nome?: string; documento?: string; email?: string; telefone?: string }>({})

  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const novos: typeof erros = {}
    const doc = somenteDigitos(documento)
    const tel = normalizarTelefone(telefone)
    if (nome.trim().length < 2) novos.nome = 'Informe o nome (mínimo 2 caracteres).'
    if (doc) {
      if (tipo === 'fisica' && doc.length !== 11) novos.documento = 'CPF deve ter 11 dígitos.'
      else if (tipo === 'juridica' && doc.length !== 14) novos.documento = 'CNPJ deve ter 14 dígitos.'
      else if (!documentoValido(doc)) novos.documento = tipo === 'fisica' ? 'CPF inválido.' : 'CNPJ inválido.'
    }
    if (email.trim() && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) novos.email = 'E-mail inválido.'
    if (tel && !telefoneValido(tel)) novos.telefone = 'Telefone com DDD (10–11 dígitos) ou internacional com "+" (ex.: +16893162446).'
    setErros(novos)
    if (Object.keys(novos).length > 0) return
    aoSalvar({ tipo, nome: nome.trim(), documento: doc || null, email: email.trim().toLowerCase() || null, telefone: tel || null, login_servidor: loginServidor.trim() || null, endereco: endereco.trim() || null, data_nascimento: nascimento || null, observacao: observacao.trim() || null, ativo, receber_avisos: receberAvisos })
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
        <Campo rotulo="Telefone" value={telefone} inputMode="tel" onChange={(e) => setTelefone(e.target.value)} onBlur={() => setTelefone(formatarTelefone(normalizarTelefone(telefone) || null))} erro={erros.telefone} placeholder="(11) 99999-9999" />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="E-mail" type="email" value={email} onChange={(e) => setEmail(e.target.value)} erro={erros.email} />
        <Campo rotulo={tipo === 'fisica' ? 'Data de nascimento' : 'Data de fundação'} type="date" value={nascimento} onChange={(e) => setNascimento(e.target.value)} max={new Date().toISOString().slice(0, 10)} />
      </div>
      <p className="-mt-2 text-xs text-ink-muted">Usada no login do portal do cliente (CPF/CNPJ + data).</p>
      <Campo rotulo="Endereço (opcional)" value={endereco} onChange={(e) => setEndereco(e.target.value)} maxLength={200} placeholder="Rua, número, bairro, cidade" />
      <Campo rotulo="Login do servidor (opcional)" value={loginServidor} onChange={(e) => setLoginServidor(e.target.value)} maxLength={60} placeholder="Ex.: joao01" />
      <p className="-mt-2 text-xs text-ink-muted">Login do cliente no servidor IPTV; usado nos Disparos para casar o PDF com o cadastro.</p>
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
        {editando && aoExcluir && (
          <Botao type="button" variante="perigo" className="mr-auto" carregando={excluindo} disabled={salvando}
            onClick={() => { if (window.confirm(`Excluir "${pessoa?.nome}"? Só é possível excluir pessoa sem histórico (contratos, lançamentos, OS…). Não dá para desfazer.`)) aoExcluir() }}>
            Excluir
          </Botao>
        )}
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando || excluindo}>Voltar</Botao>
        <Botao type="submit" carregando={salvando} disabled={excluindo}>{editando ? 'Salvar alterações' : 'Criar pessoa'}</Botao>
      </div>
    </form>
  )
}
