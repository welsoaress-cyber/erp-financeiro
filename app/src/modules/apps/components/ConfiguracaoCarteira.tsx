import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Selecao } from '../../../core/ui/Selecao'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import type { Conta } from '../../contas/tipos'
import type { Categoria } from '../../categorias/tipos'
import { useConfigurarCarteira } from '../api'
import type { ResumoCarteira } from '../tipos'

/** Conta onde o dinheiro da carteira fica e categoria da despesa de consumo. */
export function ConfiguracaoCarteira({ resumo, contas, categorias, aoConcluir }: { resumo: ResumoCarteira; contas: Conta[]; categorias: Categoria[]; aoConcluir: () => void }) {
  const configurar = useConfigurarCarteira()
  const [contaId, setContaId] = useState(resumo.conta_id ?? '')
  const [categoriaId, setCategoriaId] = useState(resumo.categoria_consumo_id ?? '')
  const [erro, setErro] = useState<string | null>(null)
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (!contaId || !categoriaId) { setErro('Informe a conta da carteira e a categoria de consumo.'); return }
    setErro(null)
    configurar.mutate({ negocioId: resumo.negocio_id, contaId, categoriaConsumoId: categoriaId }, { onSuccess: aoConcluir })
  }
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || configurar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(configurar.error)}</Alerta>}
      <Selecao rotulo="Conta da carteira" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...contas.filter((c) => c.ativo || c.id === resumo.conta_id).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={contaId} onChange={(e) => setContaId(e.target.value)} ajuda="Conta que guarda o dinheiro da carteira (ex.: Carteira Digital). Recargas entram nela; consumos saem dela." />
      <Selecao rotulo="Categoria da despesa de consumo" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...categorias.filter((c) => c.tipo === 'despesa' && (c.ativo || c.id === resumo.categoria_consumo_id)).map((c) => ({ valor: c.id, rotulo: c.categoria_pai_id ? `  ${c.nome}` : c.nome }))]} value={categoriaId} onChange={(e) => setCategoriaId(e.target.value)} />
      <p className="text-xs text-ink-muted">A receita da anuidade usa a conta e a categoria de receita padrão do negócio (menu Negócios).</p>
      <div className="flex justify-end gap-2"><Botao type="submit" carregando={configurar.isPending}>Salvar configuração</Botao></div>
    </form>
  )
}
