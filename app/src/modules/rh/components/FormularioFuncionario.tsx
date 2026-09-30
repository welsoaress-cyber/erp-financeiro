import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { SelecaoBusca } from '../../../core/ui/SelecaoBusca'
import { hojeISO } from '../../../core/formatos'
import type { Negocio } from '../../negocios/tipos'
import type { Pessoa } from '../../pessoas/tipos'
import type { DadosFuncionario, Funcionario } from '../tipos'

interface Props {
  negocios: Negocio[]
  pessoas: Pessoa[]
  funcionario?: Funcionario
  salvando: boolean
  erro: string | null
  aoSalvar: (d: DadosFuncionario) => void
  aoCancelar: () => void
}

export function FormularioFuncionario({ negocios, pessoas, funcionario, salvando, erro, aoSalvar, aoCancelar }: Props) {
  const negociosAtivos = negocios.filter((n) => n.ativo)
  const [negocioId, setNegocioId] = useState(funcionario?.negocio_id ?? (negociosAtivos.length === 1 ? negociosAtivos[0].id : ''))
  const [pessoaId, setPessoaId] = useState(funcionario?.pessoa_id ?? '')
  const [cargo, setCargo] = useState(funcionario?.cargo ?? '')
  const [departamento, setDepartamento] = useState(funcionario?.departamento ?? '')
  const [salario, setSalario] = useState(funcionario ? String(funcionario.salario_base) : '')
  const [dataAdmissao, setDataAdmissao] = useState(funcionario?.data_admissao ?? hojeISO())
  const [dataDemissao, setDataDemissao] = useState(funcionario?.data_demissao ?? '')
  const [ativo, setAtivo] = useState(funcionario?.ativo ?? true)
  const [erros, setErros] = useState<Record<string, string>>({})

  function enviar(e: FormEvent) {
    e.preventDefault()
    const novos: Record<string, string> = {}
    const v = Number(salario.replace(',', '.'))
    if (!negocioId) novos.negocio = 'Selecione o negócio.'
    if (!pessoaId) novos.pessoa = 'Selecione a pessoa.'
    if (salario.trim() === '' || Number.isNaN(v) || v < 0) novos.salario = 'Informe um salário válido.'
    if (!dataAdmissao) novos.data = 'Informe a data de admissão.'
    setErros(novos)
    if (Object.keys(novos).length) return
    aoSalvar({
      negocio_id: negocioId, pessoa_id: pessoaId, cargo: cargo.trim() || null, departamento: departamento.trim() || null,
      salario_base: Math.round(v * 100) / 100, data_admissao: dataAdmissao, data_demissao: dataDemissao || null, ativo,
    })
  }

  const erroCampo = (k: string) => erros[k] ? <p className="-mt-3 text-xs text-red-600">{erros[k]}</p> : null

  return (
    <form onSubmit={enviar} className="space-y-4" noValidate>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <Selecao rotulo="Negócio" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...negociosAtivos.map((n) => ({ valor: n.id, rotulo: n.nome }))]} value={negocioId} onChange={(e) => setNegocioId(e.target.value)} disabled={Boolean(funcionario)} />
      {erroCampo('negocio')}
      <SelecaoBusca rotulo="Pessoa" opcoes={pessoas.filter((p) => p.ativo).map((p) => ({ valor: p.id, rotulo: p.nome }))} value={pessoaId} onChange={setPessoaId} placeholder="Digite o nome pra buscar…" erro={erros.pessoa} disabled={Boolean(funcionario)} ajuda="A pessoa já precisa estar cadastrada em Pessoas — funcionário não duplica o cadastro." />
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Cargo (opcional)" value={cargo} onChange={(e) => setCargo(e.target.value)} />
        <Campo rotulo="Departamento (opcional)" value={departamento} onChange={(e) => setDepartamento(e.target.value)} />
      </div>
      <div className="grid grid-cols-3 gap-4">
        <Campo rotulo="Salário base (R$)" type="number" inputMode="decimal" step="0.01" min="0" value={salario} onChange={(e) => setSalario(e.target.value)} erro={erros.salario} />
        <Campo rotulo="Admissão" type="date" value={dataAdmissao} onChange={(e) => setDataAdmissao(e.target.value)} erro={erros.data} />
        <Campo rotulo="Demissão (opcional)" type="date" value={dataDemissao} onChange={(e) => setDataDemissao(e.target.value)} />
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} />
        <span>Ativo</span>
      </label>
      <div className="flex justify-end gap-2 pt-2">
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando}>Cancelar</Botao>
        <Botao type="submit" carregando={salvando}>{funcionario ? 'Salvar alterações' : 'Cadastrar funcionário'}</Botao>
      </div>
    </form>
  )
}
