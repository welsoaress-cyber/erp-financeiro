import { useMemo, useState } from 'react'
import { Link } from 'react-router'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { CartaoRecolhivel } from '../../../core/ui/CartaoRecolhivel'
import { Icone } from '../../../core/ui/Icone'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { SeletorMes } from '../../../core/ui/SeletorMes'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarMoedaOuOculto, mesAtualISO } from '../../../core/formatos'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { useContas } from '../../contas/api'
import { useCategorias } from '../../categorias/api'
import { ROTULO_TIPO as ROTULO_TIPO_CONTA } from '../../contas/tipos'
import { useNegocios } from '../../negocios/api'
import { ROTULO_PESSOAL } from '../../negocios/tipos'
import { useLancamentos, useProjecaoContratos } from '../../lancamentos/api'
import { montarLinhasVisaoPorNegocio, useDashboardAgenda, useResultadoPorNegocio, useSaldoInicial, useUltimosLancamentos, type PrevistoNegocio } from '../api'
import { ResumoFinanceiro } from '../components/ResumoFinanceiro'
import { AgendaFinanceira } from '../components/AgendaFinanceira'
import { PendenciasOperacionais } from '../components/PendenciasOperacionais'
import { VisaoPorNegocio } from '../components/VisaoPorNegocio'
import { MovimentacoesRecentes } from '../components/MovimentacoesRecentes'
import { HeroBoasVindas } from '../components/HeroBoasVindas'

function Indicador({ rotulo, valor, tom = 'neutro', detalhe, oculto }: { rotulo: string; valor: number; tom?: 'neutro' | 'positivo' | 'negativo' | 'auto'; detalhe?: string; oculto: boolean }) {
  const cor = tom === 'positivo' ? 'text-green-700' : tom === 'negativo' ? 'text-red-700' : tom === 'auto' ? (valor < 0 ? 'text-red-700' : 'text-green-700') : ''
  return (
    <Cartao className="p-5">
      <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">{rotulo}</p>
      <p className={`mt-2 text-2xl font-semibold tabular-nums ${cor}`}>{formatarMoedaOuOculto(valor, oculto)}</p>
      {detalhe && <p className="mt-1 text-xs tabular-nums text-ink-muted">{detalhe}</p>}
    </Cartao>
  )
}

const CHAVE_OCULTAR_VALORES = 'erp.dash.ocultarValores'
function lerOcultarValores(): boolean {
  try { return localStorage.getItem(CHAVE_OCULTAR_VALORES) === '1' } catch { return false }
}

export function DashboardPage() {
  const { organizacao } = useOrganizacao()
  const [mes, setMes] = useState(mesAtualISO())
  const [filtro, setFiltro] = useState<string>('') // '' = todos, 'pessoal', ou id do negócio
  const [oculto, setOculto] = useState(lerOcultarValores)
  const alternarOculto = () => setOculto((v) => {
    const novo = !v
    try { localStorage.setItem(CHAVE_OCULTAR_VALORES, novo ? '1' : '0') } catch { /* sem storage — vale só até recarregar */ }
    return novo
  })
  const contas = useContas()
  const categorias = useCategorias()
  const negocios = useNegocios()
  const resultado = useResultadoPorNegocio(mes)
  const ultimos = useUltimosLancamentos()
  const lancamentosMes = useLancamentos(mes)
  const projecao = useProjecaoContratos(mes)
  const saldoInicial = useSaldoInicial(mes)
  const agenda = useDashboardAgenda()

  const nomeConta = useMemo(() => new Map((contas.data ?? []).map((c) => [c.id, c.nome])), [contas.data])
  const nomeCategoria = useMemo(() => new Map((categorias.data ?? []).map((c) => [c.id, c.nome])), [categorias.data])
  const nomeNegocio = useMemo(() => new Map((negocios.data ?? []).map((n) => [n.id, n.nome])), [negocios.data])
  const rotuloNegocio = (id: string | null) => (id ? nomeNegocio.get(id) ?? '—' : ROTULO_PESSOAL)
  const bate = (negocioId: string | null) => !filtro || (filtro === 'pessoal' ? negocioId === null : negocioId === filtro)

  const contasAtivas = (contas.data ?? []).filter((c) => c.ativo && bate(c.negocio_id))
  const saldoTotal = contasAtivas.reduce((s, c) => s + Number(c.saldo), 0)
  const linhas = (resultado.data ?? []).filter((r) => bate(r.negocio_id))
  const totais = linhas.reduce((t, r) => ({ receitas: t.receitas + r.receitas, despesas: t.despesas + r.despesas, resultado: t.resultado + r.resultado }), { receitas: 0, despesas: 0, resultado: 0 })
  const ultimosFiltrados = (ultimos.data ?? []).filter((l) => bate(l.negocio_id))

  // Previsto do mês por negócio: lançamentos ainda não efetivados + projeção de contratos (meses ainda não faturados) — nunca lançamentos pré-gerados.
  const previstosPorNegocio = useMemo(() => {
    const mapa = new Map<string | null, PrevistoNegocio>()
    const soma = (negocioId: string | null, tipo: 'receita' | 'despesa', valor: number) => {
      const atual = mapa.get(negocioId) ?? { negocio_id: negocioId, receitas: 0, despesas: 0 }
      if (tipo === 'receita') atual.receitas += valor
      else atual.despesas += valor
      mapa.set(negocioId, atual)
    }
    for (const l of lancamentosMes.data ?? []) {
      if (l.status === 'previsto' && (l.tipo === 'receita' || l.tipo === 'despesa')) soma(l.negocio_id, l.tipo, l.valor)
    }
    for (const pj of projecao.data ?? []) {
      if (pj.tipo === 'receita' || pj.tipo === 'despesa') soma(pj.negocio_id, pj.tipo, Number(pj.valor))
    }
    return [...mapa.values()]
  }, [lancamentosMes.data, projecao.data])

  const previstosFiltrados = previstosPorNegocio.filter((p) => bate(p.negocio_id))
  const prev = previstosFiltrados.reduce((t, p) => ({ receitas: t.receitas + p.receitas, despesas: t.despesas + p.despesas }), { receitas: 0, despesas: 0 })

  const agendaFiltrada = (agenda.data ?? []).filter((i) => bate(i.negocio_id))
  const receber30 = agendaFiltrada.filter((i) => i.tipo === 'receita' && i.bucket !== 'mais30').reduce((s, i) => s + i.valor, 0)
  const pagar30 = agendaFiltrada.filter((i) => i.tipo === 'despesa' && i.bucket !== 'mais30').reduce((s, i) => s + i.valor, 0)

  const linhasVisaoPorNegocio = montarLinhasVisaoPorNegocio(negocios.data ?? [], resultado.data ?? [], previstosPorNegocio, bate)

  const temNegocios = (negocios.data ?? []).length > 0

  const carregando = contas.isPending || resultado.isPending || ultimos.isPending || negocios.isPending || lancamentosMes.isPending || saldoInicial.isPending || agenda.isPending
  const erro = contas.error ?? resultado.error ?? ultimos.error ?? negocios.error ?? lancamentosMes.error ?? saldoInicial.error ?? agenda.error

  return (
    <>
      <HeroBoasVindas nomeOrganizacao={organizacao.nome} />

      <CabecalhoPagina
        titulo="Dashboard"
        descricao={`Visão geral de ${organizacao.nome}`}
        acoes={
          <div className="flex flex-wrap items-start gap-2">
            <button type="button" onClick={alternarOculto} aria-pressed={oculto}
              title={oculto ? 'Mostrar valores' : 'Ocultar valores (abrir em público)'}
              className="flex h-10 items-center gap-1.5 rounded-md border border-line bg-white px-3 text-sm text-ink-muted hover:text-ink">
              <Icone nome={oculto ? 'olho_fechado' : 'olho'} className="size-4" />
              {oculto ? 'Valores ocultos' : 'Ocultar valores'}
            </button>
            {temNegocios && (
              <select aria-label="Filtrar por negócio" value={filtro} onChange={(e) => setFiltro(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
                <option value="">Todos os negócios</option>
                <option value="pessoal">{ROTULO_PESSOAL}</option>
                {(negocios.data ?? []).filter((n) => n.ativo).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
              </select>
            )}
            <SeletorMes mes={mes} aoMudar={setMes} />
          </div>
        }
      />

      {carregando && <Carregando texto="Calculando…" />}
      {erro && <Alerta tipo="erro" titulo="Não foi possível carregar o painel">{mensagemDeErro(erro)}</Alerta>}

      {contas.isSuccess && resultado.isSuccess && ultimos.isSuccess && negocios.isSuccess && lancamentosMes.isSuccess && saldoInicial.isSuccess && agenda.isSuccess && (
        <div className="space-y-6">
          {/* Resumo */}
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Indicador rotulo="Saldo total" valor={saldoTotal} tom="auto" oculto={oculto} />
            <Indicador rotulo="A receber · 30 dias" valor={receber30} tom="positivo" oculto={oculto} />
            <Indicador rotulo="A pagar · 30 dias" valor={pagar30} tom="negativo" oculto={oculto} />
            <Indicador rotulo="Resultado do mês (projetado)" valor={totais.resultado + prev.receitas - prev.despesas} tom="auto" oculto={oculto}
              detalhe={`Realizado: ${formatarMoedaOuOculto(totais.resultado, oculto)}`} />
          </div>

          {/* Agenda financeira */}
          <AgendaFinanceira itens={agenda.data ?? []} bate={bate} oculto={oculto} />

          {/* Pendências */}
          <PendenciasOperacionais bate={bate} oculto={oculto} />

          {/* Visão por negócio */}
          <VisaoPorNegocio linhas={linhasVisaoPorNegocio} oculto={oculto} />

          <ResumoFinanceiro lancamentos={lancamentosMes.data} saldoInicial={saldoInicial.data} negocioPorId={nomeNegocio} filtro={filtro} bate={bate}
            naturezaDe={new Map((categorias.data ?? []).map((c) => [c.id, c.natureza]))} oculto={oculto} />

          {/* Movimentações recentes */}
          <MovimentacoesRecentes lancamentos={ultimosFiltrados} nomeConta={nomeConta} nomeCategoria={nomeCategoria} nomeNegocio={nomeNegocio} oculto={oculto} />

          <CartaoRecolhivel
            id="saldo-por-conta"
            titulo={<h2 className="text-sm font-semibold">Saldo por conta</h2>}
            acao={<Link to="/contas" className="shrink-0 text-xs font-medium text-brand-600 hover:underline">Ver contas</Link>}
          >
            {contasAtivas.length === 0 ? (
              <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhuma conta ativa. <Link to="/contas" className="text-brand-600 hover:underline">Cadastre a primeira.</Link></p>
            ) : (
              <ul className="divide-y divide-line">
                {contasAtivas.map((c) => (
                  <li key={c.id} className="flex items-center justify-between px-6 py-3 text-sm">
                    <span><span className="font-medium">{c.nome}</span> <span className="text-xs text-ink-muted">· {ROTULO_TIPO_CONTA[c.tipo]}{temNegocios ? ` · ${rotuloNegocio(c.negocio_id)}` : ''}</span></span>
                    <span className={`font-medium tabular-nums ${Number(c.saldo) < 0 ? 'text-red-700' : ''}`}>{formatarMoedaOuOculto(c.saldo, oculto)}</span>
                  </li>
                ))}
              </ul>
            )}
          </CartaoRecolhivel>
        </div>
      )}
    </>
  )
}
