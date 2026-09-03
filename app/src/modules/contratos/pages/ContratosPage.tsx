import { useMemo, useState } from 'react'
import { Link } from 'react-router'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarMoeda } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useContratos, useCriarContrato, useGerarFaturamento, usePlanos, useReceitaRecorrente, useResultadoContratos, useUltimaExecucao } from '../api'
import { useContas } from '../../contas/api'
import { formatarData } from '../../../core/formatos'
import { FormularioContrato } from '../components/FormularioContrato'
import { DetalheContrato } from '../components/DetalheContrato'
import { codigoContrato, ROTULO_PERIODICIDADE, ROTULO_PESSOA_CONTRATO, ROTULO_STATUS_CONTRATO, type Contrato, type StatusContrato } from '../tipos'

type Edicao = { modo: 'novo' } | { modo: 'ver'; id: string } | null
const TOM: Record<StatusContrato, 'ok' | 'alerta' | 'neutro'> = { ativo: 'ok', suspenso: 'alerta', encerrado: 'neutro' }

export function ContratosPage() {
  const contratos = useContratos()
  const planos = usePlanos()
  const negocios = useNegocios()
  const pessoas = usePessoas()
  const resultado = useResultadoContratos()
  const mrr = useReceitaRecorrente()
  const criar = useCriarContrato()
  const contas = useContas()
  const execucao = useUltimaExecucao()
  const gerar = useGerarFaturamento()
  const [edicao, setEdicao] = useState<Edicao>(null)
  const [filtroNegocio, setFiltroNegocio] = useState('')
  const [filtroStatus, setFiltroStatus] = useState<StatusContrato | ''>('ativo')

  const nome = useMemo(() => ({
    negocio: new Map((negocios.data ?? []).map((n) => [n.id, n.nome])),
    pessoa: new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])),
    plano: new Map((planos.data ?? []).map((p) => [p.id, p.nome])),
  }), [negocios.data, pessoas.data, planos.data])
  const resultadoDe = useMemo(() => new Map((resultado.data ?? []).map((r) => [r.contrato_id, r])), [resultado.data])

  const lista = (contratos.data ?? []).filter((c) => (!filtroNegocio || c.negocio_id === filtroNegocio) && (!filtroStatus || c.status === filtroStatus))
  const contratoVisto = edicao?.modo === 'ver' ? (contratos.data ?? []).find((c) => c.id === edicao.id) : undefined
  const temPlanos = (planos.data ?? []).some((p) => p.ativo)
  const carregando = contratos.isPending || planos.isPending || negocios.isPending || pessoas.isPending || resultado.isPending || mrr.isPending || contas.isPending
  const erroCarga = contratos.error ?? planos.error ?? negocios.error ?? pessoas.error ?? resultado.error ?? mrr.error ?? contas.error
  const ultima = gerar.data ?? execucao.data ?? null
  const temContratosAtivos = (contratos.data ?? []).some((c) => c.status === 'ativo')

  function fechar() { criar.reset(); setEdicao(null) }

  return (
    <>
      <CabecalhoPagina titulo="Contratos" descricao="Pessoas contratando planos dos seus negócios, com rentabilidade por contrato" acoes={<div className="flex gap-2"><Botao variante="secundario" onClick={() => gerar.mutate(undefined)} carregando={gerar.isPending} disabled={!temContratosAtivos}>Gerar faturamento agora</Botao><Botao onClick={() => setEdicao({ modo: 'novo' })} disabled={!temPlanos}>Novo contrato</Botao></div>} />
      {carregando && <Carregando texto="Carregando contratos…" />}
      {erroCarga && <Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(erroCarga)}</Alerta>}
      {!carregando && !erroCarga && (
        <div className="space-y-6">
          {gerar.error && <Alerta tipo="erro" titulo="Falha ao gerar faturamento">{mensagemDeErro(gerar.error)}</Alerta>}
          {ultima && (
            <Alerta tipo={ultima.pendencias.length > 0 ? 'info' : 'sucesso'} titulo={`Último faturamento ${ultima.origem === 'agendado' ? 'automático' : 'manual'} em ${formatarData(ultima.executado_em.slice(0, 10))}: ${ultima.gerados} cobrança(s) gerada(s)`}>
              {ultima.pendencias.length > 0 && (
                <ul className="mt-1 list-disc pl-5">
                  {ultima.pendencias.map((p) => <li key={p.contrato_id}>Contrato #{String(p.codigo).padStart(3, '0')} ({nome.negocio.get(p.negocio_id) ?? '—'}): {p.motivo}</li>)}
                </ul>
              )}
              {ultima.pendencias.length === 0 && ultima.gerados === 0 && 'Nada a gerar: todas as competências até hoje já foram faturadas.'}
            </Alerta>
          )}
          {!temPlanos && <Alerta tipo="info" titulo="Cadastre planos antes">Contratos precisam de um plano. Abra o negócio em <Link to="/negocios" className="font-medium text-brand-600 hover:underline">Negócios</Link> e cadastre seus planos.</Alerta>}

          {(mrr.data ?? []).length > 0 && (
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {(mrr.data ?? []).map((m) => (
                <Cartao key={m.negocio_id} className="p-5">
                  <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">{m.negocio} · receita recorrente</p>
                  <p className="mt-2 text-2xl font-semibold tabular-nums text-green-700">{formatarMoeda(m.mrr)}<span className="text-sm font-normal text-ink-muted">/mês</span></p>
                  <p className="mt-1 text-xs text-ink-muted">{m.contratos_ativos} ativo(s){m.contratos_suspensos ? ` · ${m.contratos_suspensos} suspenso(s)` : ''}</p>
                </Cartao>
              ))}
            </div>
          )}

          <Cartao className="p-0">
            <div className="flex flex-wrap items-center gap-3 border-b border-line px-6 py-3 text-sm">
              <select aria-label="Filtrar por negócio" value={filtroNegocio} onChange={(e) => setFiltroNegocio(e.target.value)} className="h-9 rounded-md border border-line bg-white px-3 text-sm">
                <option value="">Todos os negócios</option>
                {(negocios.data ?? []).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
              </select>
              <select aria-label="Filtrar por status" value={filtroStatus} onChange={(e) => setFiltroStatus(e.target.value as StatusContrato | '')} className="h-9 rounded-md border border-line bg-white px-3 text-sm">
                <option value="">Todos os status</option>
                <option value="ativo">Ativos</option>
                <option value="suspenso">Suspensos</option>
                <option value="encerrado">Encerrados</option>
              </select>
              <span className="ml-auto text-ink-muted">{lista.length} {lista.length === 1 ? 'contrato' : 'contratos'}</span>
            </div>
            {lista.length === 0 ? (
              <div className="flex flex-col items-center gap-3 py-16 text-center">
                <p className="text-sm font-medium">Nenhum contrato {filtroStatus ? ROTULO_STATUS_CONTRATO[filtroStatus].toLowerCase() : ''}</p>
                {temPlanos && <Botao onClick={() => setEdicao({ modo: 'novo' })}>Novo contrato</Botao>}
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                    <tr className="border-b border-line">
                      <th className="px-6 py-3 font-medium">Contrato</th>
                      <th className="px-6 py-3 font-medium">Pessoa</th>
                      <th className="px-6 py-3 font-medium">Plano</th>
                      <th className="px-6 py-3 text-right font-medium">Valor</th>
                      <th className="px-6 py-3 text-right font-medium">Resultado</th>
                      <th className="px-6 py-3 font-medium">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {lista.map((c: Contrato) => {
                      const r = resultadoDe.get(c.id)
                      return (
                        <tr key={c.id} onClick={() => setEdicao({ modo: 'ver', id: c.id })} className="cursor-pointer border-b border-line last:border-0 hover:bg-surface">
                          <td className="px-6 py-3"><div className="font-medium tabular-nums">{codigoContrato(c)}</div><div className="text-xs text-ink-muted">{nome.negocio.get(c.negocio_id) ?? '—'}</div></td>
                          <td className="px-6 py-3 font-medium">{nome.pessoa.get(c.pessoa_id) ?? '—'}<div className="text-xs font-normal capitalize text-ink-muted">{ROTULO_PESSOA_CONTRATO[c.tipo_financeiro]}</div></td>
                          <td className="px-6 py-3 text-ink-muted">{nome.plano.get(c.plano_id) ?? '—'}<div className="text-xs">venc. dia {c.dia_vencimento}</div></td>
                          <td className="px-6 py-3 text-right tabular-nums">{formatarMoeda(c.valor)}<div className="text-xs text-ink-muted">{ROTULO_PERIODICIDADE[c.periodicidade]}</div></td>
                          <td className={`px-6 py-3 text-right font-medium tabular-nums ${(r?.resultado ?? 0) < 0 ? 'text-red-700' : (r?.resultado ?? 0) > 0 ? 'text-green-700' : 'text-ink-muted'}`}>{formatarMoeda(r?.resultado ?? 0)}</td>
                          <td className="px-6 py-3"><Distintivo tom={TOM[c.status]}>{ROTULO_STATUS_CONTRATO[c.status]}</Distintivo></td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </Cartao>
        </div>
      )}

      <Modal aberto={edicao !== null} aoFechar={fechar} titulo={edicao?.modo === 'novo' ? 'Novo contrato' : contratoVisto ? `Contrato ${codigoContrato(contratoVisto)}` : 'Contrato'}>
        {edicao?.modo === 'novo' && (
          <FormularioContrato negocios={negocios.data ?? []} pessoas={pessoas.data ?? []} planos={planos.data ?? []} contas={contas.data ?? []} salvando={criar.isPending} erro={criar.error ? mensagemDeErro(criar.error) : null} aoSalvar={(d) => criar.mutate(d, { onSuccess: fechar })} aoCancelar={fechar} />
        )}
        {contratoVisto && (
          <DetalheContrato key={contratoVisto.id + contratoVisto.status} contrato={contratoVisto} nomes={{ negocio: nome.negocio.get(contratoVisto.negocio_id) ?? '—', pessoa: nome.pessoa.get(contratoVisto.pessoa_id) ?? '—', plano: nome.plano.get(contratoVisto.plano_id) ?? '—' }} resultado={resultadoDe.get(contratoVisto.id)} contas={contas.data ?? []} aoFechar={fechar} />
        )}
      </Modal>
    </>
  )
}
