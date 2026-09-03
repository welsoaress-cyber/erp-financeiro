import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import type { Conta } from '../../contas/tipos'
import type { Categoria } from '../../categorias/tipos'
import { gerarSlug, SLUG_VALIDO, TIPOS_SALDO, type DadosNegocio, type Negocio, type TipoSaldo } from '../tipos'

interface Props {
  negocio?: Negocio
  contas: Conta[]
  categorias: Categoria[]
  salvando: boolean
  erro: string | null
  aoSalvar: (dados: DadosNegocio) => void
  aoCancelar: () => void
}

export function FormularioNegocio({ negocio, contas, categorias, salvando, erro, aoSalvar, aoCancelar }: Props) {
  const editando = Boolean(negocio)
  const [nome, setNome] = useState(negocio?.nome ?? '')
  const [slug, setSlug] = useState(negocio?.slug ?? '')
  const [slugManual, setSlugManual] = useState(Boolean(negocio))
  const [ativo, setAtivo] = useState(negocio?.ativo ?? true)
  const [contaPadrao, setContaPadrao] = useState(negocio?.conta_padrao_id ?? '')
  const [categoriaReceita, setCategoriaReceita] = useState(negocio?.categoria_receita_id ?? '')
  const [tipoSaldo, setTipoSaldo] = useState<TipoSaldo | ''>(negocio?.tipo_saldo ?? '')
  const [taxa, setTaxa] = useState(negocio?.taxa_conversao ? String(negocio.taxa_conversao) : '')
  const [erros, setErros] = useState<{ nome?: string; slug?: string; taxa?: string }>({})
  const taxaNum = Number(taxa.replace(',', '.'))

  function aoMudarNome(v: string) {
    setNome(v)
    if (!slugManual) setSlug(gerarSlug(v))
  }

  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const novos: typeof erros = {}
    if (nome.trim().length === 0) novos.nome = 'Informe o nome do negócio.'
    else if (nome.trim().length > 60) novos.nome = 'Máximo de 60 caracteres.'
    if (!SLUG_VALIDO.test(slug)) novos.slug = 'Use apenas letras minúsculas, números e hífens.'
    if (tipoSaldo === 'credito' && (taxa.trim() === '' || Number.isNaN(taxaNum) || taxaNum <= 0)) novos.taxa = 'Informe quantos créditos valem R$ 1,00.'
    setErros(novos)
    if (Object.keys(novos).length > 0) return
    aoSalvar({ nome: nome.trim(), slug, ativo, conta_padrao_id: contaPadrao || null, categoria_receita_id: categoriaReceita || null, tipo_saldo: tipoSaldo || null, taxa_conversao: tipoSaldo === 'credito' ? taxaNum : null })
  }

  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <Campo rotulo="Nome" value={nome} onChange={(e) => aoMudarNome(e.target.value)} erro={erros.nome} autoFocus maxLength={60} placeholder="Ex.: SERVNET" />
      <div className="space-y-1">
        <Campo rotulo="Identificador (slug)" value={slug} onChange={(e) => { setSlugManual(true); setSlug(e.target.value) }} erro={erros.slug} maxLength={40} />
        <p className="text-xs text-ink-muted">Gerado automaticamente a partir do nome. Usado em relatórios e integrações futuras.</p>
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Selecao rotulo="Conta de recebimento padrão" opcoes={[{ valor: '', rotulo: 'Não definida' }, ...contas.filter((c) => c.ativo || c.id === negocio?.conta_padrao_id).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaPadrao} onChange={(e) => setContaPadrao(e.target.value)} />
        <Selecao rotulo="Categoria de receita padrão" opcoes={[{ valor: '', rotulo: 'Não definida' }, ...categorias.filter((c) => c.tipo === 'receita' && (c.ativo || c.id === negocio?.categoria_receita_id)).map((c) => ({ valor: c.id, rotulo: c.categoria_pai_id ? `  ${c.nome}` : c.nome }))]} value={categoriaReceita} onChange={(e) => setCategoriaReceita(e.target.value)} />
      </div>
      <p className="-mt-2 text-xs text-ink-muted">Usados pelo faturamento recorrente dos contratos deste negócio.</p>
      <div className="grid grid-cols-2 gap-4">
        <Selecao rotulo="Saldo para ativação de apps" opcoes={TIPOS_SALDO} value={tipoSaldo} onChange={(e) => setTipoSaldo(e.target.value as TipoSaldo | '')} ajuda={tipoSaldo ? 'Habilita o módulo Apps para este negócio.' : undefined} />
        {tipoSaldo === 'credito' && (
          <Campo rotulo="Créditos por R$ 1,00" type="number" inputMode="decimal" step="0.0001" min="0.0001" value={taxa} onChange={(e) => { setTaxa(e.target.value); setErros((x) => ({ ...x, taxa: undefined })) }} erro={erros.taxa} placeholder="Ex.: 0,1" />
        )}
      </div>
      {tipoSaldo === 'credito' && !erros.taxa && taxaNum > 0 && <p className="-mt-2 text-xs text-ink-muted">R$ 100,00 de recarga = {(100 * taxaNum).toLocaleString('pt-BR', { maximumFractionDigits: 2 })} crédito(s); 1 crédito custa R$ {(1 / taxaNum).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}.</p>}
      {editando && (
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />
          Negócio ativo
        </label>
      )}
      <div className="flex justify-end gap-2 pt-2">
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando}>Cancelar</Botao>
        <Botao type="submit" carregando={salvando}>{editando ? 'Salvar alterações' : 'Criar negócio'}</Botao>
      </div>
    </form>
  )
}
