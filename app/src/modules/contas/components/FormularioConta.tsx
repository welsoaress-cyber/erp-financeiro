import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { hojeISO } from '../../../core/formatos'
import { TIPOS_CONTA, type Conta, type DadosConta, type TipoConta } from '../tipos'
import { SelecaoNegocio } from '../../negocios/components/SelecaoNegocio'
import type { Negocio } from '../../negocios/tipos'

interface Props {
  conta?: Conta
  negocios: Negocio[]
  salvando: boolean
  erro: string | null
  aoSalvar: (dados: DadosConta) => void
  aoCancelar: () => void
}

export function FormularioConta({ conta, negocios, salvando, erro, aoSalvar, aoCancelar }: Props) {
  const editando = Boolean(conta)
  const [nome, setNome] = useState(conta?.nome ?? '')
  const [tipo, setTipo] = useState<TipoConta>(conta?.tipo ?? 'corrente')
  const [saldoInicial, setSaldoInicial] = useState(conta ? String(conta.saldo_inicial) : '0')
  const [dataInicio, setDataInicio] = useState(conta?.data_inicio ?? hojeISO())
  const [ativo, setAtivo] = useState(conta?.ativo ?? true)
  const [negocioId, setNegocioId] = useState<string | null>(conta?.negocio_id ?? null)
  const [erros, setErros] = useState<{ nome?: string; saldo?: string; data?: string }>({})

  function validar(): boolean {
    const novos: typeof erros = {}
    if (nome.trim().length === 0) novos.nome = 'Informe o nome da conta.'
    else if (nome.trim().length > 80) novos.nome = 'Máximo de 80 caracteres.'
    const saldo = Number(saldoInicial.replace(',', '.'))
    if (saldoInicial.trim() === '' || Number.isNaN(saldo)) novos.saldo = 'Informe um valor numérico.'
    else if (saldo < 0) novos.saldo = 'O saldo inicial não pode ser negativo.'
    if (!dataInicio) novos.data = 'Informe a data de início.'
    setErros(novos)
    return Object.keys(novos).length === 0
  }

  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (!validar()) return
    aoSalvar({
      nome: nome.trim(),
      tipo,
      saldo_inicial: Math.round(Number(saldoInicial.replace(',', '.')) * 100) / 100,
      data_inicio: dataInicio,
      ativo,
      negocio_id: negocioId,
    })
  }

  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <Campo rotulo="Nome" value={nome} onChange={(e) => setNome(e.target.value)} erro={erros.nome} autoFocus maxLength={80} placeholder="Ex.: Nubank, Itaú, Dinheiro" />
      <Selecao
        rotulo="Tipo"
        opcoes={TIPOS_CONTA}
        value={tipo}
        onChange={(e) => setTipo(e.target.value as TipoConta)}
        disabled={editando}
        ajuda={editando ? 'O tipo não pode ser alterado depois de criado.' : undefined}
      />
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Saldo inicial (R$)" type="number" inputMode="decimal" step="0.01" min="0" value={saldoInicial} onChange={(e) => setSaldoInicial(e.target.value)} erro={erros.saldo} />
        <Campo rotulo="Data de início" type="date" value={dataInicio} onChange={(e) => setDataInicio(e.target.value)} erro={erros.data} />
      </div>
      <SelecaoNegocio negocios={negocios} valor={negocioId} aoMudar={setNegocioId} atualId={conta?.negocio_id} ajuda="Conta de um negócio específico ou pessoal." />
      {editando && (
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />
          Conta ativa
        </label>
      )}
      <div className="flex justify-end gap-2 pt-2">
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando}>Cancelar</Botao>
        <Botao type="submit" carregando={salvando}>{editando ? 'Salvar alterações' : 'Criar conta'}</Botao>
      </div>
    </form>
  )
}
