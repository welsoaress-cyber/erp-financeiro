import { useMemo, useState } from 'react'
import { Link } from 'react-router'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { SeletorMes } from '../../../core/ui/SeletorMes'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda, mesAtualISO } from '../../../core/formatos'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { useContas } from '../../contas/api'
import { useCategorias } from '../../categorias/api'
import { ROTULO_TIPO as ROTULO_TIPO_CONTA } from '../../contas/tipos'
import { ROTULO_TIPO } from '../../lancamentos/tipos'
import { useNegocios } from '../../negocios/api'
import { ROTULO_PESSOAL } from '../../negocios/tipos'
import { useLancamentos } from '../../lancamentos/api'
import { useResultadoPorNegocio, useSaldoInicial, useSaudeNotificacoes, useUltimosLancamentos } from '../api'
import { ResumoFinanceiro } from '../components/ResumoFinanceiro'
import { SaudeAvisos } from '../components/SaudeAvisos'

function Indicador({ rotulo, valor, tom = 'neutro', detalhe }: { rotulo: string; valor: number; tom?: 'neutro' | 'positivo' | 'negativo' | 'auto'; detalhe?: string }) {
  const cor = tom === 'positivo' ? 'text-green-700' : tom === 'negativo' ? 'text-red-700' : tom === 'auto' ? (valor < 0 ? 'text-red-700' : 'text-green-700') : ''
  return (
    <Cartao className="p-5">
      <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">{rotulo}</p>
      <p className={`mt-2 text-2xl font-semibold tabular-nums ${cor}`}>{formatarMoeda(valor)}</p>
      {detalhe && <p className="mt-1 text-xs tabular-nums text-ink-muted">{detalhe}</p>}
    </Cartao>
  )
}

export function DashboardPage() {
  const { organizacao } = useOrganizacao()
  const [mes, setMes] = useState(mesAtualISO())
  const [filtro, setFiltro] = useState<string>('') // '' = todos, 'pessoal', ou id do negócio
  const contas = useContas()
  const categorias = useCategorias()
  const negocios = useNegocios()
  const resultado = useResultadoPorNegocio(mes)
  const ultimos = useUltimosLancamentos()
  const lancamentosMes = useLancamentos(mes)
  const saldoInicial = useSaldoInicial(mes)
  const saudeNotificacoes = useSaudeNotificacoes()

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
  // Previsto do mês: lançamentos ainda não efetivados (fora cancelados), respeitando o filtro de negócio
  const previstos = (lancamentosMes.data ?? []).filter((l) => l.status === 'previsto' && bate(l.negocio_id))
  const prev = previstos.reduce((t, l) => {
    if (l.tipo === 'receita') t.receitas += l.valor
    if (l.tipo === 'despesa') t.despesas += l.valor
    return t
  }, { receitas: 0, despesas: 0 })
  const temNegocios = (negocios.data ?? []).length > 0

  const carregando = contas.isPending || resultado.isPending || ultimos.isPending || negocios.isPending || lancamentosMes.isPending || saldoInicial.isPending
  const erro = contas.error ?? resultado.error ?? ultimos.error ?? negocios.error ?? lancamentosMes.error ?? saldoInicial.error

  return (
    <>
      <CabecalhoPagina
        titulo="Dashboard"
        descricao={`Visão geral de ${organizacao.nome}`}
        acoes={
          <div className="flex flex-wrap items-center gap-2">
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

      {contas.isSuccess && resultado.isSuccess && ultimos.isSuccess && negocios.isSuccess && lancamentosMes.isSuccess && saldoInicial.isSuccess && (
        <div className="space-y-6">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Indicador rotulo="Saldo total" valor={saldoTotal} tom="auto" />
            <Indicador rotulo="Receitas do mês" valor={totais.receitas} tom="positivo" detalhe={`Previsto: ${formatarMoeda(prev.receitas)}`} />
            <Indicador rotulo="Despesas do mês" valor={totais.despesas} tom="negativo" detalhe={`Previsto: ${formatarMoeda(prev.despesas)}`} />
            <Indicador rotulo="Resultado do mês" valor={totais.resultado} tom="auto" detalhe={`Projetado (com previstos): ${formatarMoeda(totais.resultado + prev.receitas - prev.despesas)}`} />
          </div>

          <SaudeAvisos negocios={(negocios.data ?? []).filter((n) => bate(n.id))} saude={saudeNotificacoes.data} />

          <ResumoFinanceiro lancamentos={lancamentosMes.data} saldoInicial={saldoInicial.data} negocioPorId={nomeNegocio} filtro={filtro} bate={bate} />

          <div className="grid gap-6 lg:grid-cols-2">
            <Cartao className="p-0">
              <div className="flex items-center justify-between border-b border-line px-6 py-3">
                <h2 className="text-sm font-semibold">Saldo por conta</h2>
                <Link to="/contas" className="text-xs font-medium text-brand-600 hover:underline">Ver contas</Link>
              </div>
              {contasAtivas.length === 0 ? (
                <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhuma conta ativa. <Link to="/contas" className="text-brand-600 hover:underline">Cadastre a primeira.</Link></p>
              ) : (
                <ul className="divide-y divide-line">
                  {contasAtivas.map((c) => (
                    <li key={c.id} className="flex items-center justify-between px-6 py-3 text-sm">
                      <span><span className="font-medium">{c.nome}</span> <span className="text-xs text-ink-muted">· {ROTULO_TIPO_CONTA[c.tipo]}{temNegocios ? ` · ${rotuloNegocio(c.negocio_id)}` : ''}</span></span>
                      <span className={`font-medium tabular-nums ${Number(c.saldo) < 0 ? 'text-red-700' : ''}`}>{formatarMoeda(c.saldo)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </Cartao>

            <Cartao className="p-0">
              <div className="flex items-center justify-between border-b border-line px-6 py-3">
                <h2 className="text-sm font-semibold">Últimas movimentações</h2>
                <Link to="/financeiro/lancamentos" className="text-xs font-medium text-brand-600 hover:underline">Ver lançamentos</Link>
              </div>
              {ultimosFiltrados.length === 0 ? (
                <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhum lançamento efetivado ainda.</p>
              ) : (
                <ul className="divide-y divide-line">
                  {ultimosFiltrados.map((l) => (
                    <li key={l.id} className="flex items-center justify-between gap-3 px-6 py-3 text-sm">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{l.descricao}</p>
                        <p className="truncate text-xs text-ink-muted">
                          {formatarData(l.data_efetivacao ?? l.data_competencia)} · {l.tipo === 'transferencia' ? `${nomeConta.get(l.conta_id) ?? '—'} → ${nomeConta.get(l.conta_destino_id ?? '') ?? '—'}` : `${nomeCategoria.get(l.categoria_id ?? '') ?? ROTULO_TIPO[l.tipo]} · ${nomeConta.get(l.conta_id) ?? '—'}`}{l.negocio_id ? ` · ${rotuloNegocio(l.negocio_id)}` : ''}
                        </p>
                      </div>
                      <span className={`shrink-0 font-medium tabular-nums ${l.tipo === 'receita' ? 'text-green-700' : l.tipo === 'despesa' ? 'text-red-700' : 'text-brand-700'}`}>
                        {l.tipo === 'despesa' ? '− ' : l.tipo === 'receita' ? '+ ' : ''}{formatarMoeda(l.valor)}
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </Cartao>
          </div>
        </div>
      )}
    </>
  )
}
