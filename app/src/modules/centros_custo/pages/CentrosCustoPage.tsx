import { useMemo, useState } from 'react'
import { Link } from 'react-router'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { SeletorMes } from '../../../core/ui/SeletorMes'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarMoeda, mesAtualISO } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { useCtos } from '../../ftth/api'
import { useAtualizarCentroCusto, useCentrosCusto, useCriarCentroCusto, useGastosCentros } from '../api'
import { FormularioCentroCusto } from '../components/FormularioCentroCusto'
import { ROTULO_TIPO_CENTRO, type CentroCusto, type DadosCentroCusto } from '../tipos'

type Edicao = { modo: 'novo' } | { modo: 'editar'; centro: CentroCusto } | null

/** Centros de custo por negócio (etapa 54A): cadastro + gasto do mês. Sem centro = "Geral". */
export function CentrosCustoPage() {
  const centros = useCentrosCusto()
  const negocios = useNegocios()
  const pontos = useCtos()
  const criar = useCriarCentroCusto()
  const atualizar = useAtualizarCentroCusto()
  const [mes, setMes] = useState(mesAtualISO())
  const gastos = useGastosCentros(mes)
  const [negocioId, setNegocioId] = useState('')
  const [mostrarInativos, setMostrarInativos] = useState(false)
  const [edicao, setEdicao] = useState<Edicao>(null)

  const nomeNegocio = useMemo(() => new Map((negocios.data ?? []).map((n) => [n.id, n.nome])), [negocios.data])
  const gastoDe = (centroId: string | null, negocio: string | null) => {
    const ls = (gastos.data ?? []).filter((g) => g.centro_custo_id === centroId && (centroId !== null || g.negocio_id === negocio))
    return { realizado: ls.filter((g) => g.status === 'efetivado').reduce((s, g) => s + g.valor, 0), previsto: ls.filter((g) => g.status === 'previsto').reduce((s, g) => s + g.valor, 0) }
  }
  const lista = (centros.data ?? []).filter((c) => (mostrarInativos || c.ativo) && (!negocioId || c.negocio_id === negocioId))
  const totalInativos = (centros.data ?? []).filter((c) => !c.ativo).length
  const negociosVisiveis = (negocios.data ?? []).filter((n) => n.ativo && (!negocioId || n.id === negocioId))

  function fechar() { criar.reset(); atualizar.reset(); setEdicao(null) }
  function salvar(d: DadosCentroCusto) {
    if (!edicao) return
    if (edicao.modo === 'novo') criar.mutate(d, { onSuccess: fechar })
    else atualizar.mutate({ id: edicao.centro.id, ...d }, { onSuccess: fechar })
  }
  const erroSalvar = criar.error ?? atualizar.error

  return (
    <>
      <CabecalhoPagina titulo="Centros de custo" descricao="Departamentos, projetos e pontos de rede dentro de cada negócio — para saber quanto cada um custa. Lançamento sem centro = Geral."
        acoes={<Botao onClick={() => setEdicao({ modo: 'novo' })}>Novo centro de custo</Botao>} />
      <div className="mb-4 flex flex-wrap items-start gap-3">
        <select aria-label="Negócio" value={negocioId} onChange={(e) => setNegocioId(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
          <option value="">Todos os negócios</option>
          {(negocios.data ?? []).filter((n) => n.ativo).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
        </select>
        <SeletorMes mes={mes} aoMudar={setMes} />
        <Link to="/relatorios/gastos-centro-custo" className="self-center text-sm text-brand-700 hover:underline">Relatório de gastos por centro</Link>
      </div>
      {centros.isPending && <Carregando />}
      {centros.error != null && <Alerta tipo="erro">{mensagemDeErro(centros.error)}</Alerta>}
      {centros.isSuccess && (
        <Cartao className="p-0">
          <div className="flex items-center justify-between border-b border-line px-6 py-3 text-sm">
            <span className="text-ink-muted">{lista.length} centro(s) · gasto do mês (realizado · previsto)</span>
            {totalInativos > 0 && <label className="flex items-center gap-2"><input type="checkbox" checked={mostrarInativos} onChange={(e) => setMostrarInativos(e.target.checked)} className="size-4 accent-brand-600" />Mostrar inativos ({totalInativos})</label>}
          </div>
          <div className="overflow-x-auto"><table className="w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line">
              <th className="px-6 py-3 font-medium">Centro de custo</th><th className="px-6 py-3 font-medium">Tipo</th><th className="px-6 py-3 font-medium">Negócio</th>
              <th className="px-6 py-3 text-right font-medium">Realizado</th><th className="px-6 py-3 text-right font-medium">Previsto</th><th className="px-6 py-3 font-medium">Status</th>
            </tr></thead>
            <tbody>
              {lista.map((c) => { const g = gastoDe(c.id, c.negocio_id); return (
                <tr key={c.id} onClick={() => setEdicao({ modo: 'editar', centro: c })} className="cursor-pointer border-b border-line hover:bg-surface">
                  <td className="px-6 py-3 font-medium">{c.nome}{c.descricao && <div className="text-xs font-normal text-ink-muted">{c.descricao}</div>}</td>
                  <td className="px-6 py-3 text-ink-muted">{ROTULO_TIPO_CENTRO[c.tipo]}</td>
                  <td className="px-6 py-3 text-ink-muted">{nomeNegocio.get(c.negocio_id) ?? '—'}</td>
                  <td className="px-6 py-3 text-right tabular-nums">{formatarMoeda(g.realizado)}</td>
                  <td className="px-6 py-3 text-right tabular-nums text-ink-muted">{formatarMoeda(g.previsto)}</td>
                  <td className="px-6 py-3"><Distintivo tom={c.ativo ? 'ok' : 'neutro'}>{c.ativo ? 'Ativo' : 'Inativo'}</Distintivo></td>
                </tr>) })}
              {negociosVisiveis.map((n) => { const g = gastoDe(null, n.id); return (g.realizado || g.previsto) ? (
                <tr key={`geral-${n.id}`} className="border-b border-line last:border-0 bg-surface/60">
                  <td className="px-6 py-3 italic text-ink-muted">Geral (sem centro de custo)</td><td className="px-6 py-3 text-ink-muted">—</td><td className="px-6 py-3 text-ink-muted">{n.nome}</td>
                  <td className="px-6 py-3 text-right tabular-nums">{formatarMoeda(g.realizado)}</td><td className="px-6 py-3 text-right tabular-nums text-ink-muted">{formatarMoeda(g.previsto)}</td><td className="px-6 py-3"></td>
                </tr>) : null })}
            </tbody>
          </table></div>
          {lista.length === 0 && <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhum centro de custo. Comece por Administrativo, Comercial, Técnico/Rede e um por POP.</p>}
        </Cartao>
      )}
      <Modal aberto={edicao !== null} aoFechar={fechar} titulo={edicao?.modo === 'editar' ? 'Editar centro de custo' : 'Novo centro de custo'}>
        {edicao && (
          <FormularioCentroCusto key={edicao.modo === 'editar' ? edicao.centro.id : 'novo'} centro={edicao.modo === 'editar' ? edicao.centro : undefined}
            negocios={negocios.data ?? []} pontos={pontos.data ?? []} salvando={criar.isPending || atualizar.isPending}
            erro={erroSalvar ? mensagemDeErro(erroSalvar) : null} aoSalvar={salvar} aoCancelar={fechar} />
        )}
      </Modal>
    </>
  )
}
