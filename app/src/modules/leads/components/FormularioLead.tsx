import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import type { Negocio } from '../../negocios/tipos'
import type { Plano } from '../../contratos/tipos'
import type { DadosLead } from '../tipos'

interface Props {
  negocios: Negocio[]
  planos: Plano[]
  salvando: boolean
  erro: string | null
  aoSalvar: (d: DadosLead) => void
  aoCancelar: () => void
}

export function FormularioLead({ negocios, planos, salvando, erro, aoSalvar, aoCancelar }: Props) {
  const negociosAtivos = negocios.filter((n) => n.ativo)
  const [negocioId, setNegocioId] = useState(negociosAtivos.length === 1 ? negociosAtivos[0].id : '')
  const [nome, setNome] = useState('')
  const [telefone, setTelefone] = useState('')
  const [email, setEmail] = useState('')
  const [endereco, setEndereco] = useState('')
  const [planoId, setPlanoId] = useState('')
  const [observacao, setObservacao] = useState('')
  const [erros, setErros] = useState<Record<string, string>>({})
  const planosDoNegocio = planos.filter((p) => p.negocio_id === negocioId && p.ativo)

  function enviar(e: FormEvent) {
    e.preventDefault()
    const novos: Record<string, string> = {}
    if (!negocioId) novos.negocio = 'Selecione o negócio.'
    if (nome.trim().length < 2) novos.nome = 'Informe o nome.'
    if (telefone.replace(/\D/g, '').length < 10) novos.telefone = 'Telefone inválido.'
    setErros(novos)
    if (Object.keys(novos).length) return
    aoSalvar({ negocio_id: negocioId, nome: nome.trim(), telefone, email: email.trim() || null, endereco: endereco.trim() || null, plano_interesse_id: planoId || null, observacao: observacao.trim() || null })
  }

  const erroCampo = (k: string) => erros[k] ? <p className="-mt-3 text-xs text-red-600">{erros[k]}</p> : null

  return (
    <form onSubmit={enviar} className="space-y-4" noValidate>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <Selecao rotulo="Negócio" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...negociosAtivos.map((n) => ({ valor: n.id, rotulo: n.nome }))]} value={negocioId} onChange={(e) => { setNegocioId(e.target.value); setPlanoId('') }} />
      {erroCampo('negocio')}
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Nome" value={nome} onChange={(e) => setNome(e.target.value)} erro={erros.nome} autoFocus />
        <Campo rotulo="Telefone" value={telefone} onChange={(e) => setTelefone(e.target.value)} placeholder="(11) 95555-0000" erro={erros.telefone} />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="E-mail (opcional)" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        <Selecao rotulo="Plano de interesse (opcional)" opcoes={[{ valor: '', rotulo: negocioId ? 'Nenhum' : 'Escolha o negócio primeiro' }, ...planosDoNegocio.map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={planoId} onChange={(e) => setPlanoId(e.target.value)} disabled={!negocioId} />
      </div>
      <Campo rotulo="Endereço (opcional)" value={endereco} onChange={(e) => setEndereco(e.target.value)} />
      <AreaTexto rotulo="Observação (opcional)" rows={2} maxLength={500} value={observacao} onChange={(e) => setObservacao(e.target.value)} />
      <div className="flex justify-end gap-2 pt-2">
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando}>Cancelar</Botao>
        <Botao type="submit" carregando={salvando}>Salvar lead</Botao>
      </div>
    </form>
  )
}
