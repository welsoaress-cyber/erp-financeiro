import { useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Selecao } from '../../../core/ui/Selecao'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarMoeda } from '../../../core/formatos'
import { usePessoas } from '../../pessoas/api'
import { useContratos } from '../../contratos/api'
import { codigoContrato } from '../../contratos/tipos'
import { useCtos } from '../../ftth/api'
import { useAbrirOs, useTecnicos } from '../api'
import { ROTULO_TIPO_OS, type TipoOs } from '../tipos'

/** Abertura de chamado pelo admin: com cliente (e contrato) ou sem cliente (rede). */
export function NovoChamado({ negocioId, aoFechar }: { negocioId: string; aoFechar: () => void }) {
  const pessoas = usePessoas()
  const contratos = useContratos()
  const tecnicos = useTecnicos()
  const ctos = useCtos()
  const abrir = useAbrirOs()
  const [tipo, setTipo] = useState<TipoOs>('reparo')
  const [prioridade, setPrioridade] = useState('normal')
  const [pessoaId, setPessoaId] = useState('')
  const [contratoId, setContratoId] = useState('')
  const [tecnicoId, setTecnicoId] = useState('')
  const [ctoId, setCtoId] = useState('')
  const [descricao, setDescricao] = useState('')
  const [erro, setErro] = useState<string | null>(null)

  const contratosDoCliente = (contratos.data ?? []).filter((c) => c.pessoa_id === pessoaId && c.negocio_id === negocioId && c.status !== 'encerrado')
  const tecnicosAtivos = (tecnicos.data ?? []).filter((t) => t.negocio_id === negocioId && t.ativo)
  const ctosDoNegocio = (ctos.data ?? []).filter((c) => c.negocio_id === negocioId && c.tipo === 'cto')

  function salvar() {
    setErro(null)
    if (descricao.trim().length < 3) { setErro('Descreva o chamado.'); return }
    abrir.mutate({
      negocio_id: negocioId, tipo, descricao: descricao.trim(), prioridade,
      pessoa_id: pessoaId || null, contrato_id: contratoId || null, tecnico_id: tecnicoId || null, cto_id: ctoId || null,
    }, { onSuccess: aoFechar })
  }

  return (
    <div className="space-y-4">
      {(erro ?? (abrir.error ? mensagemDeErro(abrir.error) : null)) && <Alerta tipo="erro">{erro ?? mensagemDeErro(abrir.error)}</Alerta>}
      <div className="grid grid-cols-2 gap-4">
        <Selecao rotulo="Tipo" opcoes={Object.entries(ROTULO_TIPO_OS).map(([v, r]) => ({ valor: v, rotulo: r }))} value={tipo} onChange={(e) => setTipo(e.target.value as TipoOs)} />
        <Selecao rotulo="Prioridade" opcoes={[{ valor: 'normal', rotulo: 'Normal' }, { valor: 'urgente', rotulo: 'Urgente' }]} value={prioridade} onChange={(e) => setPrioridade(e.target.value)} />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Selecao rotulo="Cliente (opcional)" opcoes={[{ valor: '', rotulo: 'Sem cliente (rede)' }, ...(pessoas.data ?? []).filter((p) => p.ativo).map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={pessoaId} onChange={(e) => { setPessoaId(e.target.value); setContratoId('') }} />
        <Selecao rotulo="Contrato (opcional)" opcoes={[{ valor: '', rotulo: pessoaId ? (contratosDoCliente.length ? 'Nenhum' : 'Sem contrato') : 'Escolha o cliente' }, ...contratosDoCliente.map((c) => ({ valor: c.id, rotulo: `${codigoContrato(c)} · ${formatarMoeda(c.valor)}` }))]} value={contratoId} onChange={(e) => setContratoId(e.target.value)} disabled={!pessoaId} />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Selecao rotulo="Técnico" ajuda={tecnicoId ? undefined : 'Vazio = atribuição automática'} opcoes={[{ valor: '', rotulo: 'Automático' }, ...tecnicosAtivos.map((t) => ({ valor: t.id, rotulo: t.nome }))]} value={tecnicoId} onChange={(e) => setTecnicoId(e.target.value)} />
        <Selecao rotulo="CTO afetada (opcional)" opcoes={[{ valor: '', rotulo: 'Nenhuma' }, ...ctosDoNegocio.map((c) => ({ valor: c.id, rotulo: c.codigo }))]} value={ctoId} onChange={(e) => setCtoId(e.target.value)} />
      </div>
      <AreaTexto rotulo="Descrição" rows={3} maxLength={500} value={descricao} onChange={(e) => setDescricao(e.target.value)} placeholder="O que aconteceu / o que fazer" />
      {contratoId && (tipo === 'instalacao' || tipo === 'mudanca_endereco') && <p className="text-xs text-ink-muted">Instalação/mudança encerrada gera custo no payback do contrato e pode ter comissão (aprovada por você).</p>}
      <div className="flex justify-end gap-2">
        <Botao variante="secundario" onClick={aoFechar} disabled={abrir.isPending}>Cancelar</Botao>
        <Botao onClick={salvar} carregando={abrir.isPending}>Abrir chamado</Botao>
      </div>
    </div>
  )
}
