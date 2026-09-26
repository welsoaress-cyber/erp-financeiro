import { useState } from 'react'
import { SelecaoBusca } from '../../../core/ui/SelecaoBusca'
import { Cartao } from '../../../core/ui/Cartao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { formatarMoeda } from '../../../core/formatos'
import { usePessoas } from '../../pessoas/api'
import { useContratos, usePlanos } from '../../contratos/api'
import { useNegocios } from '../../negocios/api'
import { ROTULO_STATUS_CONTRATO, type StatusContrato } from '../../contratos/tipos'

const TOM_STATUS: Record<StatusContrato, 'ok' | 'alerta' | 'neutro'> = { ativo: 'ok', suspenso: 'alerta', encerrado: 'neutro' }

/** Consulta rápida: status (ativo/inativo) de um cliente e os planos/contratos dele, sem precisar abrir o cadastro. */
export function ConsultaCliente() {
  const pessoas = usePessoas()
  const contratos = useContratos()
  const planos = usePlanos()
  const negocios = useNegocios()
  const [pessoaId, setPessoaId] = useState('')

  const pessoa = (pessoas.data ?? []).find((p) => p.id === pessoaId)
  const contratosDoCliente = (contratos.data ?? []).filter((c) => c.pessoa_id === pessoaId)
  const nomePlano = (id: string) => (planos.data ?? []).find((p) => p.id === id)?.nome ?? '—'
  const nomeNegocio = (id: string) => (negocios.data ?? []).find((n) => n.id === id)?.nome ?? '—'

  return (
    <Cartao className="mb-4 space-y-3 p-4">
      <SelecaoBusca
        rotulo="Consultar cliente (status e planos)"
        opcoes={(pessoas.data ?? []).map((p) => ({ valor: p.id, rotulo: p.login_servidor ? `${p.nome} · ${p.login_servidor}` : p.nome }))}
        value={pessoaId}
        onChange={setPessoaId}
        placeholder="Digite o nome ou o login do cliente…"
      />
      {pessoa && (
        <div className="rounded-md border border-line bg-canvas/60 p-3 text-sm">
          <div className="flex items-center gap-2">
            <span className="font-medium">{pessoa.nome}</span>
            {pessoa.login_servidor && <span className="text-xs text-ink-muted">· login {pessoa.login_servidor}</span>}
            <Distintivo tom={pessoa.ativo ? 'ok' : 'neutro'}>{pessoa.ativo ? 'Ativa' : 'Inativa'}</Distintivo>
          </div>
          {contratosDoCliente.length === 0 ? (
            <p className="mt-2 text-xs text-ink-muted">Nenhum contrato para este cliente.</p>
          ) : (
            <ul className="mt-2 divide-y divide-line">
              {contratosDoCliente.map((c) => (
                <li key={c.id} className="flex flex-wrap items-center justify-between gap-2 py-1.5 text-xs">
                  <span>{nomePlano(c.plano_id)} <span className="text-ink-muted">· {nomeNegocio(c.negocio_id)}</span></span>
                  <span className="flex items-center gap-2">
                    <span className="tabular-nums text-ink-muted">{formatarMoeda(c.valor)}</span>
                    <Distintivo tom={TOM_STATUS[c.status]}>{ROTULO_STATUS_CONTRATO[c.status]}</Distintivo>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </Cartao>
  )
}
