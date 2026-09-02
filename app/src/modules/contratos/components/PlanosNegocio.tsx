import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarMoeda } from '../../../core/formatos'
import type { Negocio } from '../../negocios/tipos'
import { useAtualizarPlano, useCriarPlano, usePlanos } from '../api'
import { PERIODICIDADES, ROTULO_PERIODICIDADE, type Periodicidade, type Plano } from '../tipos'

/** Catálogo de planos de um negócio: lista, novo plano, editar preço/nome, ativar/inativar. */
export function PlanosNegocio({ negocio }: { negocio: Negocio }) {
  const planos = usePlanos()
  const criar = useCriarPlano()
  const atualizar = useAtualizarPlano()
  const [editando, setEditando] = useState<Plano | 'novo' | null>(null)
  const meus = (planos.data ?? []).filter((p) => p.negocio_id === negocio.id)
  const erro = criar.error ?? atualizar.error

  return (
    <div className="space-y-3 border-t border-line pt-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Planos e serviços</h3>
        {editando === null && <Botao type="button" variante="secundario" onClick={() => setEditando('novo')} disabled={!negocio.ativo}>Novo plano</Botao>}
      </div>
      {erro && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}
      {meus.length === 0 && editando === null && <p className="text-sm text-ink-muted">Nenhum plano. Cadastre o que este negócio vende para abrir contratos.</p>}
      {meus.length > 0 && (
        <ul className="divide-y divide-line rounded-md border border-line">
          {meus.map((p) => (
            <li key={p.id} className="flex items-center justify-between gap-3 px-3 py-2 text-sm">
              <button type="button" className="text-left" onClick={() => setEditando(p)}>
                <span className="font-medium">{p.nome}</span>
                <span className="text-ink-muted"> · {formatarMoeda(p.valor_tabela)} · {ROTULO_PERIODICIDADE[p.periodicidade]}</span>
              </button>
              <Distintivo tom={p.ativo ? 'ok' : 'neutro'}>{p.ativo ? 'Ativo' : 'Inativo'}</Distintivo>
            </li>
          ))}
        </ul>
      )}
      {editando !== null && (
        <FormularioPlano
          plano={editando === 'novo' ? undefined : editando}
          salvando={criar.isPending || atualizar.isPending}
          aoSalvar={(d) => {
            if (editando === 'novo') criar.mutate({ ...d, negocio_id: negocio.id }, { onSuccess: () => setEditando(null) })
            else atualizar.mutate({ id: editando.id, ...d }, { onSuccess: () => setEditando(null) })
          }}
          aoCancelar={() => { criar.reset(); atualizar.reset(); setEditando(null) }}
        />
      )}
    </div>
  )
}

function FormularioPlano({ plano, salvando, aoSalvar, aoCancelar }: { plano?: Plano; salvando: boolean; aoSalvar: (d: { nome: string; descricao: string | null; valor_tabela: number; periodicidade: Periodicidade; ativo: boolean }) => void; aoCancelar: () => void }) {
  const [nome, setNome] = useState(plano?.nome ?? '')
  const [valor, setValor] = useState(plano ? String(plano.valor_tabela) : '')
  const [periodicidade, setPeriodicidade] = useState<Periodicidade>(plano?.periodicidade ?? 'mensal')
  const [descricao, setDescricao] = useState(plano?.descricao ?? '')
  const [ativo, setAtivo] = useState(plano?.ativo ?? true)
  const [erros, setErros] = useState<{ nome?: string; valor?: string }>({})
  function enviar(e: FormEvent) {
    e.preventDefault()
    const v = Number(valor.replace(',', '.'))
    const novos: typeof erros = {}
    if (nome.trim().length === 0) novos.nome = 'Informe o nome do plano.'
    if (valor.trim() === '' || Number.isNaN(v) || v < 0) novos.valor = 'Informe um valor válido.'
    setErros(novos)
    if (Object.keys(novos).length) return
    aoSalvar({ nome: nome.trim(), descricao: descricao.trim() || null, valor_tabela: Math.round(v * 100) / 100, periodicidade, ativo })
  }
  return (
    <form onSubmit={enviar} className="space-y-3 rounded-md border border-line bg-surface/60 p-3" noValidate>
      <Campo rotulo="Nome do plano" value={nome} onChange={(e) => setNome(e.target.value)} erro={erros.nome} autoFocus maxLength={80} placeholder="Ex.: Fibra 500 Mbps" />
      <div className="grid grid-cols-2 gap-3">
        <Campo rotulo="Valor de tabela (R$)" type="number" inputMode="decimal" step="0.01" min="0" value={valor} onChange={(e) => setValor(e.target.value)} erro={erros.valor} />
        <Selecao rotulo="Periodicidade" opcoes={PERIODICIDADES} value={periodicidade} onChange={(e) => setPeriodicidade(e.target.value as Periodicidade)} />
      </div>
      <Campo rotulo="Descrição (opcional)" value={descricao} onChange={(e) => setDescricao(e.target.value)} maxLength={300} />
      {plano && (
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />Plano ativo</label>
      )}
      <div className="flex justify-end gap-2">
        <Botao type="button" variante="secundario" onClick={aoCancelar} disabled={salvando}>Cancelar</Botao>
        <Botao type="submit" carregando={salvando}>{plano ? 'Salvar plano' : 'Criar plano'}</Botao>
      </div>
    </form>
  )
}
