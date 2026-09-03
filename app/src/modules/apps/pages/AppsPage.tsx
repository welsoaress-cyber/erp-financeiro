import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../../core/formatos'
import { useContas } from '../../contas/api'
import { useCategorias } from '../../categorias/api'
import { usePessoas } from '../../pessoas/api'
import { usePlanos } from '../../contratos/api'
import { codigoContrato } from '../../contratos/tipos'
import { useAppsCatalogo, useContratosApp, useResumosCarteira, useTransacoesCarteira } from '../api'
import { ConfiguracaoCarteira } from '../components/ConfiguracaoCarteira'
import { Recarga } from '../components/Recarga'
import { FormularioApp } from '../components/FormularioApp'
import { AtivarApp } from '../components/AtivarApp'
import { ROTULO_SITUACAO, formatarSaldo, type AppCatalogo, type SituacaoContratoApp } from '../tipos'

type Janela = { tipo: 'config' } | { tipo: 'recarga' } | { tipo: 'app'; app?: AppCatalogo } | { tipo: 'ativar' } | null
const TOM_SITUACAO: Record<SituacaoContratoApp, 'ok' | 'alerta' | 'neutro'> = { ativo: 'ok', vencido: 'alerta', cancelado: 'neutro' }

function Indicador({ rotulo, valor, detalhe }: { rotulo: string; valor: string; detalhe?: string }) {
  return (
    <Cartao className="p-4">
      <p className="text-xs uppercase tracking-wide text-ink-muted">{rotulo}</p>
      <p className="mt-1 text-xl font-semibold tabular-nums">{valor}</p>
      {detalhe && <p className="text-xs text-ink-muted">{detalhe}</p>}
    </Cartao>
  )
}

export function AppsPage() {
  const resumos = useResumosCarteira()
  const catalogo = useAppsCatalogo()
  const contas = useContas()
  const categorias = useCategorias()
  const pessoas = usePessoas()
  const planos = usePlanos()
  const [negocioSel, setNegocioSel] = useState('')
  const [janela, setJanela] = useState<Janela>(null)

  const lista = resumos.data ?? []
  const resumo = lista.find((r) => r.negocio_id === negocioSel) ?? lista[0] ?? null
  const transacoes = useTransacoesCarteira(resumo?.negocio_id ?? null)
  const contratos = useContratosApp(resumo?.negocio_id ?? null)
  const apps = useMemo(() => (catalogo.data ?? []).filter((a) => a.negocio_id === resumo?.negocio_id), [catalogo.data, resumo])
  const nomeApp = useMemo(() => new Map(apps.map((a) => [a.id, a.nome])), [apps])
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const anuidadePlano = useMemo(() => new Map((planos.data ?? []).map((p) => [p.id, p.valor_tabela])), [planos.data])
  const configurada = Boolean(resumo?.carteira_id)
  const fechar = () => setJanela(null)

  if (resumos.isPending) return <><CabecalhoPagina titulo="Apps" descricao="Saldo para ativação de apps" /><Carregando texto="Carregando…" /></>
  if (resumos.isError) return <><CabecalhoPagina titulo="Apps" /><Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(resumos.error)}</Alerta></>

  return (
    <>
      <CabecalhoPagina
        titulo="Apps"
        descricao="Saldo para ativação de apps: carteira, catálogo, ativações e contratos de anuidade"
        acoes={resumo && configurada ? (
          <>
            <Botao variante="secundario" onClick={() => setJanela({ tipo: 'recarga' })}>Recarregar</Botao>
            <Botao onClick={() => setJanela({ tipo: 'ativar' })} disabled={apps.filter((a) => a.ativo).length === 0}>Ativar app</Botao>
          </>
        ) : undefined}
      />

      {!resumo && (
        <Alerta tipo="info" titulo="Nenhum negócio opera carteira">
          No menu <Link to="/negocios" className="underline">Negócios</Link>, edite o negócio (ex.: "Ativação de App") e defina o saldo para ativação como Dinheiro ou Créditos.
        </Alerta>
      )}

      {resumo && (
        <div className="space-y-6">
          <div className="flex flex-wrap items-center gap-3">
            {lista.length > 1 && (
              <select aria-label="Negócio da carteira" value={resumo.negocio_id} onChange={(e) => setNegocioSel(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
                {lista.map((r) => <option key={r.negocio_id} value={r.negocio_id}>{r.negocio}</option>)}
              </select>
            )}
            <span className="text-sm text-ink-muted">{resumo.negocio} · modo {resumo.tipo_saldo === 'credito' ? `créditos (${resumo.taxa_conversao} por R$ 1,00)` : 'dinheiro'}</span>
            <Botao variante="secundario" className="ml-auto" onClick={() => setJanela({ tipo: 'config' })}>{configurada ? 'Configurar carteira' : 'Configurar carteira agora'}</Botao>
          </div>

          {!configurada && <Alerta tipo="info" titulo="Carteira não configurada">Defina a conta que guarda o dinheiro da carteira e a categoria da despesa de consumo para começar a recarregar.</Alerta>}

          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
            <Indicador rotulo="Saldo disponível" valor={formatarSaldo(resumo.saldo, resumo.tipo_saldo)} />
            <Indicador rotulo="Total recargas" valor={formatarSaldo(resumo.total_recargas, resumo.tipo_saldo)} />
            <Indicador rotulo="Total consumido" valor={formatarSaldo(resumo.total_consumos, resumo.tipo_saldo)} />
            <Indicador rotulo="Apps ativos" valor={String(resumo.apps_ativos)} detalhe="contratos ativos" />
            <Indicador rotulo="Receita mensal" valor={formatarMoeda(resumo.anuidades_ativas / 12)} detalhe={`${formatarMoeda(resumo.anuidades_ativas)} em anuidades ativas`} />
          </div>

          <div className="grid gap-6 lg:grid-cols-2">
            <Cartao>
              <div className="mb-3 flex items-center justify-between">
                <h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Catálogo de apps</h2>
                <Botao variante="secundario" onClick={() => setJanela({ tipo: 'app' })} disabled={!configurada}>Novo app</Botao>
              </div>
              {apps.length === 0 ? <p className="text-sm text-ink-muted">Nenhum app cadastrado.</p> : (
                <ul className="divide-y divide-line rounded-md border border-line">
                  {apps.map((a) => (
                    <li key={a.id} className="flex items-center justify-between gap-3 px-3 py-2 text-sm">
                      <button type="button" className="text-left" onClick={() => setJanela({ tipo: 'app', app: a })}>
                        <span className="font-medium">{a.nome}</span>
                        <span className="text-ink-muted"> · custo {formatarSaldo(a.custo, resumo.tipo_saldo)} · anuidade {formatarMoeda(anuidadePlano.get(a.plano_id) ?? 0)}</span>
                      </button>
                      <Distintivo tom={a.ativo ? 'ok' : 'neutro'}>{a.ativo ? 'Ativo' : 'Inativo'}</Distintivo>
                    </li>
                  ))}
                </ul>
              )}
            </Cartao>

            <Cartao>
              <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-ink-muted">Histórico da carteira</h2>
              {transacoes.isPending && configurada ? <Carregando /> : (transacoes.data ?? []).length === 0 ? <p className="text-sm text-ink-muted">Nenhuma transação. Use "Recarregar" para colocar saldo.</p> : (
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr><th className="py-2 pr-3">Data</th><th className="py-2 pr-3">Tipo</th><th className="py-2 pr-3">Detalhe</th><th className="py-2 text-right">Valor</th></tr></thead>
                    <tbody className="divide-y divide-line">
                      {(transacoes.data ?? []).map((t) => (
                        <tr key={t.id}>
                          <td className="py-2 pr-3 tabular-nums text-ink-muted">{formatarData(t.data)}</td>
                          <td className="py-2 pr-3"><Distintivo tom={t.tipo === 'recarga' ? 'ok' : 'neutro'}>{t.tipo === 'recarga' ? 'Recarga' : 'Consumo'}</Distintivo></td>
                          <td className="py-2 pr-3 text-ink-muted">{t.tipo === 'consumo' ? `${nomeApp.get(t.app_id ?? '') ?? 'App'} · ${formatarMoeda(t.valor_reais)}` : `${formatarMoeda(t.valor_reais)} pagos`}{t.observacao ? ` · ${t.observacao}` : ''}</td>
                          <td className={`py-2 text-right font-medium tabular-nums ${t.tipo === 'recarga' ? 'text-green-700' : 'text-red-700'}`}>{t.tipo === 'recarga' ? '+ ' : '− '}{formatarSaldo(t.valor, resumo.tipo_saldo)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </Cartao>
          </div>

          <Cartao className="p-0">
            <div className="border-b border-line px-6 py-3"><h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Contratos de app</h2></div>
            {(contratos.data ?? []).length === 0 ? <p className="px-6 py-8 text-center text-sm text-ink-muted">Nenhuma ativação ainda.</p> : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-6 py-3 font-medium">Contrato</th><th className="px-6 py-3 font-medium">Cliente</th><th className="px-6 py-3 font-medium">App</th><th className="px-6 py-3 text-right font-medium">Anuidade</th><th className="px-6 py-3 font-medium">Próximo vencimento</th><th className="px-6 py-3 font-medium">Situação</th></tr></thead>
                  <tbody>
                    {(contratos.data ?? []).map((c) => (
                      <tr key={c.contrato_id} className="border-b border-line last:border-0">
                        <td className="px-6 py-3 font-mono text-xs">{codigoContrato(c)}</td>
                        <td className="px-6 py-3 font-medium">{nomePessoa.get(c.pessoa_id) ?? '—'}</td>
                        <td className="px-6 py-3">{c.app}</td>
                        <td className="px-6 py-3 text-right tabular-nums">{formatarMoeda(c.anuidade)}</td>
                        <td className="px-6 py-3 tabular-nums text-ink-muted">{c.proximo_vencimento ? formatarData(c.proximo_vencimento) : '—'}</td>
                        <td className="px-6 py-3"><Distintivo tom={TOM_SITUACAO[c.situacao]}>{ROTULO_SITUACAO[c.situacao]}</Distintivo></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            <p className="px-6 py-3 text-xs text-ink-muted">Encerramento e detalhes no menu <Link to="/contratos" className="underline">Contratos</Link>. Vencido = anuidade prevista com vencimento passado.</p>
          </Cartao>
        </div>
      )}

      {resumo && (
        <Modal aberto={janela !== null} aoFechar={fechar} titulo={janela?.tipo === 'config' ? 'Configurar carteira' : janela?.tipo === 'recarga' ? 'Recarregar carteira' : janela?.tipo === 'ativar' ? 'Ativar app' : janela?.app ? 'Editar app' : 'Novo app'}>
          {janela?.tipo === 'config' && <ConfiguracaoCarteira resumo={resumo} contas={contas.data ?? []} categorias={categorias.data ?? []} aoConcluir={fechar} />}
          {janela?.tipo === 'recarga' && <Recarga resumo={resumo} contas={contas.data ?? []} aoConcluir={fechar} />}
          {janela?.tipo === 'app' && <FormularioApp resumo={resumo} app={janela.app} anuidadeAtual={janela.app ? anuidadePlano.get(janela.app.plano_id) : undefined} aoConcluir={fechar} />}
          {janela?.tipo === 'ativar' && <AtivarApp resumo={resumo} apps={apps} planos={planos.data ?? []} pessoas={pessoas.data ?? []} aoConcluir={fechar} />}
        </Modal>
      )}
    </>
  )
}
