import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
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
import { useResultadoMensal, useUltimosLancamentos } from '../api'
import { ROTULO_TIPO } from '../../lancamentos/tipos'

function Indicador({ rotulo, valor, tom = 'neutro' }: { rotulo: string; valor: number; tom?: 'neutro' | 'positivo' | 'negativo' | 'auto' }) {
  const cor = tom === 'positivo' ? 'text-green-700' : tom === 'negativo' ? 'text-red-700' : tom === 'auto' ? (valor < 0 ? 'text-red-700' : 'text-green-700') : ''
  return (
    <Cartao className="p-5">
      <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">{rotulo}</p>
      <p className={`mt-2 text-2xl font-semibold tabular-nums ${cor}`}>{formatarMoeda(valor)}</p>
    </Cartao>
  )
}

export function DashboardPage() {
  const { organizacao } = useOrganizacao()
  const [mes, setMes] = useState(mesAtualISO())
  const contas = useContas()
  const categorias = useCategorias()
  const resultado = useResultadoMensal(mes)
  const ultimos = useUltimosLancamentos()

  const ativas = (contas.data ?? []).filter((c) => c.ativo)
  const saldoTotal = ativas.reduce((s, c) => s + Number(c.saldo), 0)
  const nomeConta = useMemo(() => new Map((contas.data ?? []).map((c) => [c.id, c.nome])), [contas.data])
  const nomeCategoria = useMemo(() => new Map((categorias.data ?? []).map((c) => [c.id, c.nome])), [categorias.data])

  const carregando = contas.isPending || resultado.isPending || ultimos.isPending
  const erro = contas.error ?? resultado.error ?? ultimos.error

  return (
    <>
      <CabecalhoPagina titulo="Dashboard" descricao={`Visão geral de ${organizacao.nome}`} acoes={<SeletorMes mes={mes} aoMudar={setMes} />} />

      {carregando && <Carregando texto="Calculando…" />}
      {erro && <Alerta tipo="erro" titulo="Não foi possível carregar o painel">{mensagemDeErro(erro)}</Alerta>}

      {contas.isSuccess && resultado.isSuccess && ultimos.isSuccess && (
        <div className="space-y-6">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Indicador rotulo="Saldo total" valor={saldoTotal} tom="auto" />
            <Indicador rotulo="Receitas do mês" valor={resultado.data.receitas} tom="positivo" />
            <Indicador rotulo="Despesas do mês" valor={resultado.data.despesas} tom="negativo" />
            <Indicador rotulo="Resultado do mês" valor={resultado.data.resultado} tom="auto" />
          </div>

          <div className="grid gap-6 lg:grid-cols-2">
            <Cartao className="p-0">
              <div className="flex items-center justify-between border-b border-line px-6 py-3">
                <h2 className="text-sm font-semibold">Saldo por conta</h2>
                <Link to="/contas" className="text-xs font-medium text-brand-600 hover:underline">Ver contas</Link>
              </div>
              {ativas.length === 0 ? (
                <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhuma conta ativa. <Link to="/contas" className="text-brand-600 hover:underline">Cadastre a primeira.</Link></p>
              ) : (
                <ul className="divide-y divide-line">
                  {ativas.map((c) => (
                    <li key={c.id} className="flex items-center justify-between px-6 py-3 text-sm">
                      <span><span className="font-medium">{c.nome}</span> <span className="text-xs text-ink-muted">· {ROTULO_TIPO_CONTA[c.tipo]}</span></span>
                      <span className={`font-medium tabular-nums ${Number(c.saldo) < 0 ? 'text-red-700' : ''}`}>{formatarMoeda(c.saldo)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </Cartao>

            <Cartao className="p-0">
              <div className="flex items-center justify-between border-b border-line px-6 py-3">
                <h2 className="text-sm font-semibold">Últimas movimentações</h2>
                <Link to="/lancamentos" className="text-xs font-medium text-brand-600 hover:underline">Ver lançamentos</Link>
              </div>
              {ultimos.data.length === 0 ? (
                <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhum lançamento efetivado ainda.</p>
              ) : (
                <ul className="divide-y divide-line">
                  {ultimos.data.map((l) => (
                    <li key={l.id} className="flex items-center justify-between gap-3 px-6 py-3 text-sm">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{l.descricao}</p>
                        <p className="truncate text-xs text-ink-muted">
                          {formatarData(l.data_efetivacao ?? l.data_competencia)} · {l.tipo === 'transferencia' ? `${nomeConta.get(l.conta_id) ?? '—'} → ${nomeConta.get(l.conta_destino_id ?? '') ?? '—'}` : `${nomeCategoria.get(l.categoria_id ?? '') ?? ROTULO_TIPO[l.tipo]} · ${nomeConta.get(l.conta_id) ?? '—'}`}
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
