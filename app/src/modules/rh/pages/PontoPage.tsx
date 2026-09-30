import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { BarraFiltros, CampoBusca, ContagemFiltro, SelectFiltro } from '../../../core/ui/Filtros'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useFuncionarios, usePontoGeral } from '../api'
import { horasTrabalhadas } from '../tipos'

/** Ponto de todos os funcionários — visão agregada. Ponto informal, sem valor jurídico (ver detalhe do funcionário em RH). */
export function PontoPage() {
  const ponto = usePontoGeral()
  const funcionarios = useFuncionarios()
  const negocios = useNegocios()
  const pessoas = usePessoas()
  const [busca, setBusca] = useState('')
  const [filtroNegocio, setFiltroNegocio] = useState('')

  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const nomeNegocio = useMemo(() => new Map((negocios.data ?? []).map((n) => [n.id, n.nome])), [negocios.data])
  const funcionarioPorId = useMemo(() => new Map((funcionarios.data ?? []).map((f) => [f.id, f])), [funcionarios.data])

  const termo = busca.trim().toLowerCase()
  const base = ponto.data ?? []
  const lista = base.filter((p) => {
    const f = funcionarioPorId.get(p.funcionario_id)
    if (!f) return false
    if (filtroNegocio && f.negocio_id !== filtroNegocio) return false
    if (!termo) return true
    return (nomePessoa.get(f.pessoa_id) ?? '').toLowerCase().includes(termo)
  })

  const carregando = ponto.isPending || funcionarios.isPending || negocios.isPending || pessoas.isPending
  const erro = ponto.error ?? funcionarios.error ?? negocios.error ?? pessoas.error

  return (
    <>
      <CabecalhoPagina titulo="Ponto" descricao="Ponto informal de todos os funcionários — controle interno, sem valor jurídico pleno" />
      {carregando && <Carregando texto="Carregando ponto…" />}
      {erro && <Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(erro)}</Alerta>}

      {ponto.isSuccess && funcionarios.isSuccess && (
        <Cartao className="p-0">
          <BarraFiltros>
            <CampoBusca valor={busca} aoMudar={setBusca} rotulo="Buscar por funcionário" />
            <ContagemFiltro visiveis={lista.length} total={base.length} singular="registro" plural="registros" />
            <SelectFiltro valor={filtroNegocio} aoMudar={setFiltroNegocio} rotulo="Filtrar por negócio">
              <option value="">Todos os negócios</option>
              {(negocios.data ?? []).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
            </SelectFiltro>
          </BarraFiltros>
          {lista.length === 0 ? (
            <p className="px-6 py-16 text-center text-sm text-ink-muted">Nenhum registro de ponto ainda. Registre pelo detalhe do funcionário, em RH → Funcionários.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                  <tr className="border-b border-line">
                    <th className="px-6 py-3 font-medium">Funcionário</th>
                    <th className="px-6 py-3 font-medium">Negócio</th>
                    <th className="px-6 py-3 font-medium">Data</th>
                    <th className="px-6 py-3 font-medium">Entrada</th>
                    <th className="px-6 py-3 font-medium">Saída almoço</th>
                    <th className="px-6 py-3 font-medium">Volta almoço</th>
                    <th className="px-6 py-3 font-medium">Saída</th>
                    <th className="px-6 py-3 text-right font-medium">Horas</th>
                  </tr>
                </thead>
                <tbody>
                  {lista.map((p) => {
                    const f = funcionarioPorId.get(p.funcionario_id)
                    return (
                      <tr key={p.id} className="border-b border-line last:border-0">
                        <td className="px-6 py-3">{f ? (nomePessoa.get(f.pessoa_id) ?? '—') : '—'}</td>
                        <td className="px-6 py-3 text-xs text-ink-muted">{f ? (nomeNegocio.get(f.negocio_id) ?? '—') : '—'}</td>
                        <td className="px-6 py-3 tabular-nums">{formatarData(p.data)}</td>
                        <td className="px-6 py-3 tabular-nums">{p.entrada ?? '—'}</td>
                        <td className="px-6 py-3 tabular-nums">{p.saida_almoco ?? '—'}</td>
                        <td className="px-6 py-3 tabular-nums">{p.volta_almoco ?? '—'}</td>
                        <td className="px-6 py-3 tabular-nums">{p.saida ?? '—'}</td>
                        <td className="px-6 py-3 text-right tabular-nums">{horasTrabalhadas(p) ?? '—'}</td>
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
