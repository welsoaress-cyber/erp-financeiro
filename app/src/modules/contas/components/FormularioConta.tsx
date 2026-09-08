import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { formatarMoeda, hojeISO } from '../../../core/formatos'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { useAjustarSaldo } from '../api'
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

/** Ajuste de saldo: informa o saldo real e o sistema lança a diferença como receita/despesa efetivada. */
function AjusteSaldo({ conta }: { conta: Conta }) {
  const ajustar = useAjustarSaldo()
  const [saldoReal, setSaldoReal] = useState('')
  const [ok, setOk] = useState(false)
  const v = Number(saldoReal.replace(',', '.'))
  const diferenca = saldoReal.trim() !== '' && !Number.isNaN(v) ? Math.round((v - conta.saldo) * 100) / 100 : null
  return (
    <div className="rounded-md border border-line bg-surface/60 p-3">
      <p className="text-sm font-medium">Ajuste de saldo</p>
      <p className="mt-1 text-xs text-ink-muted">Saldo atual: {formatarMoeda(conta.saldo)}. Informe o saldo real e a diferença vira um lançamento efetivado "Ajuste de saldo".</p>
      <div className="mt-2 flex items-end gap-2">
        <div className="flex-1"><Campo rotulo="Saldo real (R$)" type="number" inputMode="decimal" step="0.01" value={saldoReal} onChange={(e) => { setSaldoReal(e.target.value); setOk(false) }} /></div>
        <Botao
          type="button"
          carregando={ajustar.isPending}
          disabled={diferenca === null || diferenca === 0}
          onClick={() => ajustar.mutate({ contaId: conta.id, diferenca: diferenca! }, { onSuccess: () => { setOk(true); setSaldoReal('') } })}
        >
          Ajustar
        </Botao>
      </div>
      {diferenca !== null && diferenca !== 0 && (
        <p className="mt-1 text-xs text-ink-muted">Será lançada uma {diferenca > 0 ? 'receita' : 'despesa'} de {formatarMoeda(Math.abs(diferenca))}.</p>
      )}
      {diferenca === 0 && <p className="mt-1 text-xs text-ink-muted">O saldo já está igual — nada a ajustar.</p>}
      {ajustar.error != null && <p className="mt-1 text-xs text-red-600">{mensagemDeErro(ajustar.error)}</p>}
      {ok && <p className="mt-1 text-xs text-green-700">Saldo ajustado.</p>}
    </div>
  )
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
      {editando && conta && conta.tipo !== 'credito' && <AjusteSaldo conta={conta} />}
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
