import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { useAtualizarApp, useCriarApp } from '../api'
import type { AppCatalogo, ResumoCarteira } from '../tipos'

export function FormularioApp({ app, anuidadeAtual, resumo, aoConcluir }: { app?: AppCatalogo; anuidadeAtual?: number; resumo: ResumoCarteira; aoConcluir: () => void }) {
  const criar = useCriarApp()
  const atualizar = useAtualizarApp()
  const [nome, setNome] = useState(app?.nome ?? '')
  const [anuidade, setAnuidade] = useState(anuidadeAtual !== undefined ? String(anuidadeAtual) : '')
  const [ativo, setAtivo] = useState(app?.ativo ?? true)
  const [erro, setErro] = useState<string | null>(null)
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const a = Number(anuidade.replace(',', '.'))
    if (nome.trim().length === 0) { setErro('Informe o nome do app.'); return }
    if (!app && (anuidade.trim() === '' || Number.isNaN(a) || a < 0)) { setErro('Informe o valor da anuidade cobrada do cliente.'); return }
    setErro(null)
    if (app) atualizar.mutate({ id: app.id, nome: nome.trim(), ativo }, { onSuccess: aoConcluir })
    else criar.mutate({ negocioId: resumo.negocio_id, nome: nome.trim(), anuidade: Math.round(a * 100) / 100 }, { onSuccess: aoConcluir })
  }
  const err = erro ?? (criar.error ? mensagemDeErro(criar.error) : atualizar.error ? mensagemDeErro(atualizar.error) : null)
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {err && <Alerta tipo="erro">{err}</Alerta>}
      <Campo rotulo="Nome do app" value={nome} onChange={(e) => setNome(e.target.value)} autoFocus maxLength={80} placeholder="Ex.: NINJA PLAYER" />
      {app
        ? <div className="text-sm"><span className="block font-medium text-ink">Anuidade (R$)</span><span className="text-ink-muted">{anuidadeAtual?.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })} · altere no plano do negócio</span></div>
        : <Campo rotulo="Anuidade cobrada do cliente (R$)" type="number" inputMode="decimal" step="0.01" min="0" value={anuidade} onChange={(e) => setAnuidade(e.target.value)} />}
      {app && (
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />App ativo (disponível para ativação)</label>
      )}
      <p className="text-xs text-ink-muted">{app ? 'O valor pago em cada ativação é informado na hora — não há custo fixo cadastrado.' : 'Cria um plano anual no negócio com este nome e valor. A ativação abre um contrato desse plano; o valor pago (dinheiro ou crédito) é informado a cada ativação.'}</p>
      <div className="flex justify-end gap-2"><Botao type="submit" carregando={criar.isPending || atualizar.isPending}>{app ? 'Salvar alterações' : 'Criar app'}</Botao></div>
    </form>
  )
}
