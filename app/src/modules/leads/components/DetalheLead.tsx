import { useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Selecao } from '../../../core/ui/Selecao'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { Distintivo } from '../../../core/ui/Distintivo'
import { Carregando } from '../../../core/ui/Carregando'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData } from '../../../core/formatos'
import { formatarTelefone } from '../../pessoas/tipos'
import { useLeadEventos, useMoverLead, useRegistrarInteracao } from '../api'
import { ROTULO_INTERACAO_LEAD, ROTULO_ORIGEM_LEAD, ROTULO_STATUS_LEAD, STATUS_LEAD, TIPOS_INTERACAO_LEAD, type Lead, type TipoInteracaoLead } from '../tipos'

const TOM_STATUS: Record<Lead['status'], 'ok' | 'alerta' | 'neutro' | 'info'> = { novo: 'info', contatado: 'info', qualificado: 'alerta', negociando: 'alerta', fechado: 'ok', perdido: 'neutro' }

interface Props {
  lead: Lead
  nomeNegocio: string
  nomePlano: string | null
  aoConverter: () => void
  convertendo: boolean
  erroConverter: string | null
}

export function DetalheLead({ lead, nomeNegocio, nomePlano, aoConverter, convertendo, erroConverter }: Props) {
  const eventos = useLeadEventos(lead.id)
  const mover = useMoverLead()
  const registrar = useRegistrarInteracao()
  const [tipo, setTipo] = useState<TipoInteracaoLead>('ligacao')
  const [descricao, setDescricao] = useState('')

  function enviarInteracao() {
    registrar.mutate({ lead_id: lead.id, tipo, descricao: descricao.trim() || null }, { onSuccess: () => setDescricao('') })
  }

  return (
    <div className="space-y-4 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <Distintivo tom={TOM_STATUS[lead.status]}>{ROTULO_STATUS_LEAD[lead.status]}</Distintivo>
        <Distintivo tom="neutro">{ROTULO_ORIGEM_LEAD[lead.origem]}</Distintivo>
        {lead.convertido_pessoa_id && <Distintivo tom="ok">Convertido em cliente</Distintivo>}
      </div>
      <div className="grid grid-cols-2 gap-3 text-ink-muted">
        <p><span className="font-medium text-ink">Negócio:</span> {nomeNegocio}</p>
        <p><span className="font-medium text-ink">Telefone:</span> {formatarTelefone(lead.telefone)}</p>
        <p><span className="font-medium text-ink">E-mail:</span> {lead.email ?? '—'}</p>
        <p><span className="font-medium text-ink">Plano de interesse:</span> {nomePlano ?? '—'}</p>
        <p className="col-span-2"><span className="font-medium text-ink">Endereço:</span> {lead.endereco ?? '—'}</p>
        {lead.observacao && <p className="col-span-2"><span className="font-medium text-ink">Observação:</span> {lead.observacao}</p>}
      </div>

      {!lead.convertido_pessoa_id && (
        <div className="flex flex-wrap items-end gap-2 rounded-md border border-line p-3">
          <div className="flex-1">
            <Selecao rotulo="Mover para" opcoes={STATUS_LEAD.map((s) => ({ valor: s, rotulo: ROTULO_STATUS_LEAD[s] }))} value={lead.status} onChange={(e) => mover.mutate({ id: lead.id, status: e.target.value as Lead['status'] })} disabled={mover.isPending} />
          </div>
          {erroConverter && <Alerta tipo="erro">{erroConverter}</Alerta>}
          <Botao variante="secundario" onClick={aoConverter} carregando={convertendo}>Converter em cliente</Botao>
        </div>
      )}
      {mover.error && <Alerta tipo="erro">{mensagemDeErro(mover.error)}</Alerta>}

      <div className="space-y-2">
        <p className="font-medium">Registrar interação</p>
        {registrar.error && <Alerta tipo="erro">{mensagemDeErro(registrar.error)}</Alerta>}
        <div className="flex flex-wrap items-end gap-2">
          <Selecao rotulo="Tipo" opcoes={TIPOS_INTERACAO_LEAD.map((t) => ({ valor: t, rotulo: ROTULO_INTERACAO_LEAD[t] }))} value={tipo} onChange={(e) => setTipo(e.target.value as TipoInteracaoLead)} />
          <div className="flex-1"><AreaTexto rotulo="Descrição (opcional)" rows={1} maxLength={500} value={descricao} onChange={(e) => setDescricao(e.target.value)} /></div>
          <Botao variante="secundario" onClick={enviarInteracao} carregando={registrar.isPending}>Registrar</Botao>
        </div>
      </div>

      <div>
        <p className="mb-2 font-medium">Histórico de interações</p>
        {eventos.isPending && <Carregando texto="Carregando…" />}
        {eventos.isSuccess && eventos.data.length === 0 && <p className="text-ink-muted">Nenhuma interação registrada ainda.</p>}
        {eventos.isSuccess && eventos.data.length > 0 && (
          <ul className="divide-y divide-line rounded-md border border-line">
            {eventos.data.map((ev) => (
              <li key={ev.id} className="px-3 py-2">
                <p><span className="font-medium">{ROTULO_INTERACAO_LEAD[ev.tipo]}</span> <span className="text-xs text-ink-muted">{formatarData(ev.criado_em.slice(0, 10))}</span></p>
                {ev.descricao && <p className="text-ink-muted">{ev.descricao}</p>}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}
