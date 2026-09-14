import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import type { Negocio } from '../../negocios/tipos'
import type { Cto } from '../../ftth/tipos'
import { ROTULO_TIPO_CENTRO, type CentroCusto, type DadosCentroCusto, type TipoCentroCusto } from '../tipos'

interface Props {
  centro?: CentroCusto
  negocios: Negocio[]
  pontos: Cto[]
  salvando: boolean
  erro: string | null
  aoSalvar: (dados: DadosCentroCusto) => void
  aoCancelar: () => void
}

export function FormularioCentroCusto({ centro, negocios, pontos, salvando, erro, aoSalvar, aoCancelar }: Props) {
  const ativos = negocios.filter((n) => n.ativo || n.id === centro?.negocio_id)
  const [negocioId, setNegocioId] = useState(centro?.negocio_id ?? (ativos.length === 1 ? ativos[0].id : ''))
  const [nome, setNome] = useState(centro?.nome ?? '')
  const [descricao, setDescricao] = useState(centro?.descricao ?? '')
  const [tipo, setTipo] = useState<TipoCentroCusto>(centro?.tipo ?? 'departamento')
  const [referenciaId, setReferenciaId] = useState(centro?.referencia_id ?? '')
  const [ativo, setAtivo] = useState(centro?.ativo ?? true)
  const [erros, setErros] = useState<Record<string, string>>({})
  const pontosDoNegocio = pontos.filter((p) => p.negocio_id === negocioId)

  function enviar(e: FormEvent) {
    e.preventDefault()
    const novos: Record<string, string> = {}
    if (!negocioId) novos.negocio = 'Selecione o negócio.'
    if (nome.trim().length < 2) novos.nome = 'Informe o nome (mínimo 2 caracteres).'
    if (tipo === 'ponto_rede' && !referenciaId) novos.referencia = 'Escolha o ponto de rede.'
    setErros(novos)
    if (Object.keys(novos).length) return
    aoSalvar({ negocio_id: negocioId, nome: nome.trim(), descricao: descricao.trim() || null, tipo, referencia_id: tipo === 'ponto_rede' ? referenciaId : null, ativo })
  }

  return (
    <form onSubmit={enviar} className="space-y-4" noValidate>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <Selecao rotulo="Negócio" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...ativos.map((n) => ({ valor: n.id, rotulo: n.nome }))]} value={negocioId} onChange={(e) => { setNegocioId(e.target.value); setReferenciaId('') }} disabled={Boolean(centro)} ajuda={centro ? 'O centro de custo não muda de negócio.' : undefined} />
      {erros.negocio && <p className="-mt-3 text-xs text-red-600">{erros.negocio}</p>}
      <Campo rotulo="Nome" value={nome} onChange={(e) => setNome(e.target.value)} erro={erros.nome} autoFocus maxLength={80} placeholder="Ex.: Administrativo, POP Centro, Projeto expansão bairro X" />
      <Selecao rotulo="Tipo" opcoes={(Object.keys(ROTULO_TIPO_CENTRO) as TipoCentroCusto[]).map((t) => ({ valor: t, rotulo: ROTULO_TIPO_CENTRO[t] }))} value={tipo} onChange={(e) => setTipo(e.target.value as TipoCentroCusto)} />
      {tipo === 'ponto_rede' && (
        <>
          <Selecao rotulo="Ponto de rede" opcoes={[{ valor: '', rotulo: negocioId ? (pontosDoNegocio.length ? 'Selecione…' : 'Este negócio não tem pontos na Rede FTTH') : 'Escolha o negócio primeiro' }, ...pontosDoNegocio.map((p) => ({ valor: p.id, rotulo: `${p.tipo.toUpperCase()} ${p.codigo}` }))]} value={referenciaId} onChange={(e) => setReferenciaId(e.target.value)} disabled={pontosDoNegocio.length === 0} ajuda="O custo acumulado deste centro é o custo do ponto." />
          {erros.referencia && <p className="-mt-3 text-xs text-red-600">{erros.referencia}</p>}
        </>
      )}
      <AreaTexto rotulo="Descrição (opcional)" rows={2} maxLength={300} value={descricao} onChange={(e) => setDescricao(e.target.value)} />
      {centro && (
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />Ativo (inativo não aparece para novos lançamentos; o histórico fica)</label>
      )}
      <div className="flex justify-end gap-2 border-t border-line pt-3">
        <Botao type="button" variante="secundario" onClick={aoCancelar}>Cancelar</Botao>
        <Botao type="submit" carregando={salvando}>{centro ? 'Salvar' : 'Criar centro de custo'}</Botao>
      </div>
    </form>
  )
}
