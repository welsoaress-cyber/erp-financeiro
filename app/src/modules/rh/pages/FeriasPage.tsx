import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Distintivo } from '../../../core/ui/Distintivo'
import { BarraFiltros, CampoBusca, ContagemFiltro, SelectFiltro } from '../../../core/ui/Filtros'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useFeriasGeral, useFuncionarios } from '../api'
import { ROTULO_STATUS_FERIAS, type StatusFerias } from '../tipos'

const TOM_FERIAS: Record<StatusFerias, 'ok' | 'alerta' | 'info' | 'neutro'> = {
  programada: 'alerta', em_gozo: 'info', concluida: 'ok', cancelada: 'neutro',
}

/** Férias de todos os funcionários — visão agregada (tracker de datas, sem cálculo de 1/3 constitucional). */
export function FeriasPage() {
  const ferias = useFeriasGeral()
  const funcionarios = useFuncionarios()
  const negocios = useNegocios()
  const pessoas = usePessoas()
  const [busca, setBusca] = useState('')
  const [filtroNegocio, setFiltroNegocio] = useState('')
  const [filtroStatus, setFiltroStatus] = useState<StatusFerias | ''>('')

  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const nomeNegocio = useMemo(() => new Map((negocios.data ?? []).map((n) => [n.id, n.nome])), [negocios.data])
  const funcionarioPorId = useMemo(() => new Map((funcionarios.data ?? []).map((f) => [f.id, f])), [funcionarios.data])

  const termo = busca.trim().toLowerCase()
  const base = ferias.data ?? []
  const lista = base.filter((f) => {
    const func = funcionarioPorId.get(f.funcionario_id)
    if (!func) return false
    if (filtroNegocio && func.negocio_id !== filtroNegocio) return false
    if (filtroStatus && f.status !== filtroStatus) return false
    if (!termo) return true
    return (nomePessoa.get(func.pessoa_id) ?? '').toLowerCase().includes(termo)
  })

  const carregando = ferias.isPending || funcionarios.isPending || negocios.isPending || pessoas.isPending
  const erro = ferias.error ?? funcionarios.error ?? negocios.error ?? pessoas.error

  return (
    <>
      <CabecalhoPagina titulo="Férias" descricao="Tracker de datas de férias de todos os funcionários — sem 1/3 constitucional nem abono" />
      {carregando && <Carregando texto="Carregando férias…" />}
      {erro && <Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(erro)}</Alerta>}

      {ferias.isSuccess && funcionarios.isSuccess && (
        <Cartao className="p-0">
          <BarraFiltros>
            <CampoBusca valor={busca} aoMudar={setBusca} rotulo="Buscar por funcionário" />
            <ContagemFiltro visiveis={lista.length} total={base.length} singular="registro" plural="registros" />
            <SelectFiltro valor={filtroNegocio} aoMudar={setFiltroNegocio} rotulo="Filtrar por negócio">
              <option value="">Todos os negócios</option>
              {(negocios.data ?? []).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
            </SelectFiltro>
            <SelectFiltro valor={filtroStatus} aoMudar={(v) => setFiltroStatus(v as StatusFerias | '')} rotulo="Filtrar por status">
              <option value="">Todos os status</option>
              {Object.entries(ROTULO_STATUS_FERIAS).map(([v, r]) => <option key={v} value={v}>{r}</option>)}
            </SelectFiltro>
          </BarraFiltros>
          {lista.length === 0 ? (
            <p className="px-6 py-16 text-center text-sm text-ink-muted">Nenhuma férias programada ainda. Programe pelo detalhe do funcionário, em RH → Funcionários.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                  <tr className="border-b border-line">
                    <th className="px-6 py-3 font-medium">Funcionário</th>
                    <th className="px-6 py-3 font-medium">Negócio</th>
                    <th className="px-6 py-3 font-medium">Período aquisitivo</th>
                    <th className="px-6 py-3 font-medium">Gozo</th>
                    <th className="px-6 py-3 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {lista.map((f) => {
                    const func = funcionarioPorId.get(f.funcionario_id)
                    return (
                      <tr key={f.id} className="border-b border-line last:border-0">
                        <td className="px-6 py-3">{func ? (nomePessoa.get(func.pessoa_id) ?? '—') : '—'}</td>
                        <td className="px-6 py-3 text-xs text-ink-muted">{func ? (nomeNegocio.get(func.negocio_id) ?? '—') : '—'}</td>
                        <td className="px-6 py-3 tabular-nums">{formatarData(f.periodo_aquisitivo_inicio)} – {formatarData(f.periodo_aquisitivo_fim)}</td>
                        <td className="px-6 py-3 tabular-nums">{f.data_inicio ? `${formatarData(f.data_inicio)} – ${f.data_fim ? formatarData(f.data_fim) : '—'}` : '—'}</td>
                        <td className="px-6 py-3"><Distintivo tom={TOM_FERIAS[f.status]}>{ROTULO_STATUS_FERIAS[f.status]}</Distintivo></td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </Cartao>
      )}
    </>
  )
}
