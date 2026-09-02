import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { TIPOS_CATEGORIA, type Categoria, type DadosCategoria, type TipoCategoria } from '../tipos'

interface Props {
  categoria?: Categoria
  todas: Categoria[]
  tipoInicial: TipoCategoria
  paiInicial?: string | null
  salvando: boolean
  erro: string | null
  aoSalvar: (dados: DadosCategoria) => void
  aoCancelar: () => void
}

export function FormularioCategoria({ categoria, todas, tipoInicial, paiInicial, salvando, erro, aoSalvar, aoCancelar }: Props) {
  const editando = Boolean(categoria)
  const [nome, setNome] = useState(categoria?.nome ?? '')
  const [tipo, setTipo] = useState<TipoCategoria>(categoria?.tipo ?? tipoInicial)
  const [paiId, setPaiId] = useState<string>(categoria?.categoria_pai_id ?? paiInicial ?? '')
  const [ativo, setAtivo] = useState(categoria?.ativo ?? true)
  const [erroNome, setErroNome] = useState<string | null>(null)

  const temFilhas = editando && todas.some((c) => c.categoria_pai_id === categoria!.id)
  // Pais possíveis: raízes ativas do mesmo tipo, exceto a própria categoria.
  const opcoesPai = todas
    .filter((c) => c.tipo === tipo && c.categoria_pai_id === null && c.ativo && c.id !== categoria?.id)
    .sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR'))

  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const limpo = nome.trim()
    if (limpo.length === 0) return setErroNome('Informe o nome da categoria.')
    if (limpo.length > 60) return setErroNome('Máximo de 60 caracteres.')
    setErroNome(null)
    aoSalvar({ nome: limpo, tipo, categoria_pai_id: paiId || null, ativo })
  }

  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <Campo rotulo="Nome" value={nome} onChange={(e) => setNome(e.target.value)} erro={erroNome ?? undefined} autoFocus maxLength={60} placeholder="Ex.: Supermercado" />
      <Selecao
        rotulo="Tipo"
        opcoes={TIPOS_CATEGORIA}
        value={tipo}
        onChange={(e) => { setTipo(e.target.value as TipoCategoria); setPaiId('') }}
        disabled={editando}
        ajuda={editando ? 'O tipo não pode ser alterado depois de criado.' : undefined}
      />
      <Selecao
        rotulo="Categoria pai (opcional)"
        opcoes={[{ valor: '', rotulo: 'Nenhuma (categoria principal)' }, ...opcoesPai.map((c) => ({ valor: c.id, rotulo: c.nome }))]}
        value={paiId}
        onChange={(e) => setPaiId(e.target.value)}
        disabled={temFilhas}
        ajuda={temFilhas ? 'Esta categoria possui subcategorias e não pode virar subcategoria.' : 'Somente categorias principais do mesmo tipo podem ser pai.'}
      />
      {editando && (
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />
          Categoria ativa
        </label>
      )}
      <div className="flex justify-end gap-2 pt-2">
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando}>Cancelar</Botao>
        <Botao type="submit" carregando={salvando}>{editando ? 'Salvar alterações' : 'Criar categoria'}</Botao>
      </div>
    </form>
  )
}
