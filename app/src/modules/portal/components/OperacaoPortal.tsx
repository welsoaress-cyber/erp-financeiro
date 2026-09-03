import { useState, type FormEvent } from 'react'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData } from '../../../core/formatos'
import { useResponderSolicitacao, useSalvarStatusRede, useSolicitacoesAdmin, useStatusRedeAdmin } from '../api'
import { ROTULO_REDE, type SolicitacaoAdmin, type StatusRede } from '../tipos'

const TIPO = { suporte: 'Suporte', fatura: 'Fatura', duvida: 'Dúvida', upgrade: 'Upgrade' } as const
const STATUS = { aberta: 'Aberto', em_andamento: 'Em andamento', concluida: 'Concluído' } as const

/** Operação do portal: status da rede (aviso aos clientes) e chamados abertos pelos clientes. */
export function OperacaoPortal({ negocioId }: { negocioId: string }) {
  const rede = useStatusRedeAdmin(); const salvarRede = useSalvarStatusRede()
  const solicitacoes = useSolicitacoesAdmin(); const responder = useResponderSolicitacao()
  const atual = (rede.data ?? []).find((r) => r.negocio_id === negocioId) ?? null
  const [status, setStatus] = useState<StatusRede>(atual?.status ?? 'ok'); const [titulo, setTitulo] = useState(atual?.titulo ?? ''); const [descricao, setDescricao] = useState(atual?.descricao ?? '')
  const [respondendo, setRespondendo] = useState<SolicitacaoAdmin | null>(null); const [resposta, setResposta] = useState(''); const [novoStatus, setNovoStatus] = useState<SolicitacaoAdmin['status']>('concluida')
  const [filtro, setFiltro] = useState<'abertos' | 'todos'>('abertos')
  function salvarStatus(e: FormEvent) {
    e.preventDefault()
    salvarRede.mutate({ id: atual?.id, negocioId, status, titulo: titulo.trim() || null, descricao: descricao.trim() || null })
  }
  const lista = (solicitacoes.data ?? []).filter((s) => s.negocio_id === negocioId && (filtro === 'todos' || s.status !== 'concluida'))
  return (
    <div className="grid gap-6 lg:grid-cols-2">
      <Cartao>
        <h2 className="mb-1 text-sm font-semibold uppercase tracking-wide text-ink-muted">Status da rede</h2>
        <p className="mb-3 text-xs text-ink-muted">Aparece no início do portal enquanto não estiver "Operando normalmente".</p>
        <form onSubmit={salvarStatus} className="space-y-3" noValidate>
          {salvarRede.error && <Alerta tipo="erro">{mensagemDeErro(salvarRede.error)}</Alerta>}
          {salvarRede.isSuccess && <Alerta tipo="sucesso">Status atualizado.</Alerta>}
          <Selecao rotulo="Situação" opcoes={(Object.keys(ROTULO_REDE) as StatusRede[]).map((s) => ({ valor: s, rotulo: ROTULO_REDE[s] }))} value={status} onChange={(e) => setStatus(e.target.value as StatusRede)} />
          {status !== 'ok' && <>
            <Campo rotulo="Título do aviso" value={titulo} onChange={(e) => setTitulo(e.target.value)} maxLength={120} placeholder="Ex.: Lentidão no bairro Centro" />
            <Campo rotulo="Detalhes (opcional)" value={descricao} onChange={(e) => setDescricao(e.target.value)} maxLength={500} placeholder="Ex.: previsão de normalização às 18h" />
          </>}
          <div className="flex items-center justify-between"><span className="text-xs text-ink-muted">{atual ? `Atualizado em ${formatarData(atual.atualizado_em.slice(0, 10))}` : 'Nunca informado'}</span><Botao type="submit" carregando={salvarRede.isPending}>Salvar status</Botao></div>
        </form>
      </Cartao>
      <Cartao className="p-0">
        <div className="flex items-center justify-between border-b border-line px-6 py-3"><h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Chamados do portal</h2><select aria-label="Filtrar chamados" value={filtro} onChange={(e) => setFiltro(e.target.value as 'abertos' | 'todos')} className="h-8 rounded-md border border-line bg-white px-2 text-xs"><option value="abertos">Abertos</option><option value="todos">Todos</option></select></div>
        {responder.error && <div className="p-4"><Alerta tipo="erro">{mensagemDeErro(responder.error)}</Alerta></div>}
        {lista.length === 0 ? <p className="px-6 py-8 text-center text-sm text-ink-muted">Nenhum chamado.</p> : (
          <ul className="divide-y divide-line">{lista.map((s) => (
            <li key={s.id} className="px-6 py-3 text-sm">
              <div className="flex items-center justify-between gap-2"><span><span className="font-mono text-xs text-ink-muted">{s.protocolo}</span> · <b>{s.pessoa}</b> · {TIPO[s.tipo]}</span><Distintivo tom={s.status === 'concluida' ? 'ok' : s.status === 'em_andamento' ? 'info' : 'alerta'}>{STATUS[s.status]}</Distintivo></div>
              {s.descricao && <p className="mt-1 text-ink-muted">{s.descricao}</p>}
              {s.resposta && <p className="mt-1 text-xs"><b>Resposta:</b> {s.resposta}</p>}
              <div className="mt-1 flex items-center justify-between"><span className="text-xs text-ink-muted">{formatarData(s.criado_em.slice(0, 10))}</span>{s.status !== 'concluida' && <button type="button" className="text-xs text-brand-700 hover:underline" onClick={() => { setRespondendo(s); setResposta(s.resposta ?? ''); setNovoStatus(s.status === 'aberta' ? 'em_andamento' : 'concluida') }}>Responder</button>}</div>
              {respondendo?.id === s.id && (
                <form className="mt-2 space-y-2 rounded-md border border-line bg-surface p-3" onSubmit={(e) => { e.preventDefault(); responder.mutate({ id: s.id, status: novoStatus, resposta: resposta.trim() || null }, { onSuccess: () => setRespondendo(null) }) }}>
                  <Selecao rotulo="Novo status" opcoes={[{ valor: 'em_andamento', rotulo: 'Em andamento' }, { valor: 'concluida', rotulo: 'Concluído' }]} value={novoStatus} onChange={(e) => setNovoStatus(e.target.value as SolicitacaoAdmin['status'])} />
                  <Campo rotulo="Resposta ao cliente" value={resposta} onChange={(e) => setResposta(e.target.value)} maxLength={1000} />
                  <div className="flex justify-end gap-2"><Botao variante="secundario" type="button" onClick={() => setRespondendo(null)}>Cancelar</Botao><Botao type="submit" carregando={responder.isPending}>Salvar</Botao></div>
                </form>
              )}
            </li>))}</ul>
        )}
      </Cartao>
    </div>
  )
}
