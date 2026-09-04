import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { SeletorMes } from '../../../core/ui/SeletorMes'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda, hojeISO, mesAtualISO } from '../../../core/formatos'
import { usePeriodo } from '../../../core/periodo/usePeriodo'
import { usePessoas } from '../../pessoas/api'
import { useContratos } from '../../contratos/api'
import { codigoContrato } from '../../contratos/tipos'
import { useBaixaParcial, useCancelarLancamento, useEfetivarLancamento, useLancamentos, useLancamentosVencidosAntes } from '../../lancamentos/api'
import { rotuloParcela, type Lancamento } from '../../lancamentos/tipos'

const diasAtraso = (vencimento: string) => Math.max(0, Math.round((Date.parse(hojeISO()) - Date.parse(vencimento)) / 86400000))

/** Previstos vencidos antes do mês corrente: fica visível não importa em qual mês o usuário esteja navegando. */
function PendenciasAnteriores({ tipo, aoAbrirAcao }: { tipo: 'receita' | 'despesa'; aoAbrirAcao: (l: Lancamento) => void }) {
  const receber = tipo === 'receita'
  const vencidos = useLancamentosVencidosAntes(tipo, mesAtualISO())
  if (!vencidos.data || vencidos.data.length === 0) return null
  const total = vencidos.data.reduce((s, l) => s + l.valor, 0)
  return (
    <Alerta tipo="erro" titulo={`${vencidos.data.length} pendência(s) de meses anteriores · ${formatarMoeda(total)}`}>
      <ul className="mt-1 divide-y divide-red-200/60">
        {vencidos.data.slice(0, 8).map((l) => (
          <li key={l.id} className="flex flex-wrap items-center justify-between gap-2 py-1.5">
            <span>{l.descricao} · vencido em {formatarData(l.data_vencimento)} (há {diasAtraso(l.data_vencimento)} dia(s)) · {formatarMoeda(l.valor)}</span>
            <button type="button" className="font-medium underline" onClick={() => aoAbrirAcao(l)}>{receber ? 'Receber' : 'Pagar'}</button>
          </li>
        ))}
      </ul>
      {vencidos.data.length > 8 && <p className="mt-1 text-xs">+ {vencidos.data.length - 8} outro(s).</p>}
    </Alerta>
  )
}

type Situacao = 'aberto' | 'vencido' | 'pago'
const situacaoDe = (l: Lancamento): Situacao => (l.status === 'efetivado' ? 'pago' : l.data_vencimento < hojeISO() ? 'vencido' : 'aberto')
const ROTULO: Record<Situacao, string> = { aberto: 'Em aberto', vencido: 'Vencido', pago: 'Pago' }
const TOM: Record<Situacao, 'ok' | 'alerta' | 'info'> = { pago: 'ok', vencido: 'alerta', aberto: 'info' }
type Acao = { tipo: 'baixa' | 'parcial' | 'cancelar'; l: Lancamento } | null

function Indicador({ rotulo, valor, tom, ajuda }: { rotulo: string; valor: string; tom?: 'ok' | 'alerta'; ajuda?: string }) {
  return <Cartao className="p-4"><p className="text-xs uppercase tracking-wide text-ink-muted">{rotulo}</p><p className={`mt-1 whitespace-nowrap text-xl font-semibold tabular-nums ${tom === 'ok' ? 'text-green-700' : tom === 'alerta' ? 'text-red-700' : ''}`}>{valor}</p>{ajuda && <p className="text-xs text-ink-muted">{ajuda}</p>}</Cartao>
}

/** Contas a receber (receitas) e contas a pagar (despesas) do mês: previsto × realizado, filtros e baixas. */
function ContasPage({ tipo }: { tipo: 'receita' | 'despesa' }) {
  const receber = tipo === 'receita'
  const { mes, setMes } = usePeriodo()
  const lancamentos = useLancamentos(mes); const pessoas = usePessoas(); const contratos = useContratos()
  const efetivar = useEfetivarLancamento(); const parcial = useBaixaParcial(); const cancelar = useCancelarLancamento()
  const [filtroPessoa, setFiltroPessoa] = useState(''); const [filtroSituacao, setFiltroSituacao] = useState<Situacao | ''>('')
  const [acao, setAcao] = useState<Acao>(null); const [dataBaixa, setDataBaixa] = useState(hojeISO()); const [valorParcial, setValorParcial] = useState(''); const [motivo, setMotivo] = useState('')
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const contratoPorId = useMemo(() => new Map((contratos.data ?? []).map((c) => [c.id, c])), [contratos.data])
  const base = (lancamentos.data ?? []).filter((l) => l.tipo === tipo && l.status !== 'cancelado')
  const lista = base.filter((l) => (!filtroPessoa || l.pessoa_id === filtroPessoa) && (!filtroSituacao || situacaoDe(l) === filtroSituacao)).sort((a, b) => a.data_vencimento.localeCompare(b.data_vencimento))
  const previsto = base.filter((l) => l.status === 'previsto').reduce((s, l) => s + l.valor, 0)
  const realizado = base.filter((l) => l.status === 'efetivado').reduce((s, l) => s + l.valor, 0)
  const saldo = realizado - previsto
  const vencidos = base.filter((l) => situacaoDe(l) === 'vencido')
  const pessoasComLanc = (pessoas.data ?? []).filter((p) => base.some((l) => l.pessoa_id === p.id))
  const erro = efetivar.error ?? parcial.error ?? cancelar.error
  const ocupado = efetivar.isPending || parcial.isPending || cancelar.isPending
  function fechar() { efetivar.reset(); parcial.reset(); cancelar.reset(); setAcao(null); setValorParcial(''); setMotivo(''); setDataBaixa(hojeISO()) }
  function confirmar() {
    if (!acao) return
    if (acao.tipo === 'baixa') efetivar.mutate({ id: acao.l.id, data_efetivacao: dataBaixa }, { onSuccess: fechar })
    if (acao.tipo === 'parcial') parcial.mutate({ id: acao.l.id, valor: Math.round(Number(valorParcial.replace(',', '.')) * 100) / 100, data_efetivacao: dataBaixa }, { onSuccess: fechar })
    if (acao.tipo === 'cancelar') cancelar.mutate({ id: acao.l.id, motivo }, { onSuccess: fechar })
  }
  const vParcial = Number(valorParcial.replace(',', '.'))
  const parcialValido = acao?.tipo === 'parcial' && vParcial > 0 && vParcial < acao.l.valor
  return (
    <>
      <CabecalhoPagina titulo={receber ? 'Contas a receber' : 'Contas a pagar'} descricao={receber ? 'Faturas e receitas do mês: previsto × realizado' : 'Compromissos com fornecedores: previsto × realizado'} />
      <div className="mb-4"><PendenciasAnteriores tipo={tipo} aoAbrirAcao={(l) => setAcao({ tipo: 'baixa', l })} /></div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SeletorMes mes={mes} aoMudar={setMes} />
        <select aria-label={receber ? 'Filtrar por cliente' : 'Filtrar por fornecedor'} value={filtroPessoa} onChange={(e) => setFiltroPessoa(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
          <option value="">{receber ? 'Todos os clientes' : 'Todos os fornecedores'}</option>
          {pessoasComLanc.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
        </select>
        <select aria-label="Filtrar por situação" value={filtroSituacao} onChange={(e) => setFiltroSituacao(e.target.value as Situacao | '')} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
          <option value="">Todas as situações</option><option value="aberto">Em aberto</option><option value="vencido">Vencidos</option><option value="pago">{receber ? 'Recebidos' : 'Pagos'}</option>
        </select>
      </div>
      <div className="mb-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Indicador rotulo="Previsto" valor={formatarMoeda(previsto)} ajuda="lançamentos ainda previstos" />
        <Indicador rotulo="Realizado" valor={formatarMoeda(realizado)} tom="ok" ajuda={receber ? 'já recebido no mês' : 'já pago no mês'} />
        <Indicador rotulo="Saldo (realizado − previsto)" valor={`${saldo >= 0 ? '+' : '−'} ${formatarMoeda(Math.abs(saldo))}`} tom={saldo >= 0 ? 'ok' : 'alerta'} ajuda={saldo >= 0 ? 'superávit' : 'déficit'} />
        <Indicador rotulo="Vencidos" valor={`${vencidos.length} · ${formatarMoeda(vencidos.reduce((s, l) => s + l.valor, 0))}`} tom={vencidos.length ? 'alerta' : undefined} />
      </div>
      {lancamentos.isPending && <Carregando />}
      {lancamentos.error && <Alerta tipo="erro">{mensagemDeErro(lancamentos.error)}</Alerta>}
      {lancamentos.isSuccess && (
        <Cartao className="p-0">
          {lista.length === 0 ? <p className="px-6 py-14 text-center text-sm text-ink-muted">Nada {receber ? 'a receber' : 'a pagar'} com esses filtros neste mês.</p> : (
            <div className="overflow-x-auto"><table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="whitespace-nowrap px-4 py-3 font-medium">Vencimento</th><th className="px-4 py-3 font-medium">Descrição</th><th className="whitespace-nowrap px-4 py-3 font-medium">{receber ? 'Cliente' : 'Fornecedor'}</th><th className="whitespace-nowrap px-4 py-3 text-right font-medium">Valor</th><th className="whitespace-nowrap px-4 py-3 font-medium">Situação</th><th className="px-4 py-3"></th></tr></thead>
              <tbody>{lista.map((l) => { const st = situacaoDe(l); const c = l.contrato_id ? contratoPorId.get(l.contrato_id) : undefined; return (
                <tr key={l.id} className="border-b border-line last:border-0 hover:bg-surface">
                  <td className="whitespace-nowrap px-4 py-3 tabular-nums">{formatarData(l.data_vencimento)}</td>
                  <td className="px-4 py-3"><span className="font-medium">{l.descricao}</span>{c && <span className="ml-2 font-mono text-xs text-ink-muted">{codigoContrato(c)}</span>}{l.recorrente && <span className="ml-2 text-xs text-ink-muted">🔄 {rotuloParcela(l)}</span>}{l.observacao && <p className="text-xs text-ink-muted">{l.observacao}</p>}</td>
                  <td className="whitespace-nowrap px-4 py-3">{l.pessoa_id ? nomePessoa.get(l.pessoa_id) ?? '—' : '—'}</td>
                  <td className="whitespace-nowrap px-4 py-3 text-right font-medium tabular-nums">{formatarMoeda(l.valor)}</td>
                  <td className="whitespace-nowrap px-4 py-3"><Distintivo tom={TOM[st]}>{st === 'pago' ? (receber ? 'Recebido' : 'Pago') : ROTULO[st]}</Distintivo>{l.data_efetivacao && <span className="ml-1 text-xs text-ink-muted">{formatarData(l.data_efetivacao)}</span>}</td>
                  <td className="whitespace-nowrap px-4 py-3 text-right">{l.status === 'previsto' && <><button type="button" className="text-brand-700 hover:underline" onClick={() => setAcao({ tipo: 'baixa', l })}>{receber ? 'Receber' : 'Pagar'}</button><button type="button" className="ml-3 text-brand-700 hover:underline" onClick={() => setAcao({ tipo: 'parcial', l })}>Baixa parcial</button><button type="button" className="ml-3 text-ink-muted hover:underline" onClick={() => setAcao({ tipo: 'cancelar', l })}>Cancelar</button></>}</td>
                </tr>) })}</tbody>
            </table></div>
          )}
        </Cartao>
      )}
      <Modal aberto={acao !== null} aoFechar={fechar} largura="md" titulo={acao?.tipo === 'baixa' ? (receber ? 'Marcar como recebido' : 'Marcar como pago') : acao?.tipo === 'parcial' ? 'Baixa parcial' : 'Cancelar lançamento'}>
        {acao && (
          <div className="space-y-4">
            {erro && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}
            <p className="text-sm"><span className="font-medium">{acao.l.descricao}</span> · {formatarMoeda(acao.l.valor)} · vence {formatarData(acao.l.data_vencimento)}</p>
            {acao.tipo !== 'cancelar' && <Campo rotulo={receber ? 'Data do recebimento' : 'Data do pagamento'} type="date" value={dataBaixa} onChange={(e) => setDataBaixa(e.target.value)} />}
            {acao.tipo === 'parcial' && <><Campo rotulo={receber ? 'Valor recebido (R$)' : 'Valor pago (R$)'} type="number" step="0.01" min="0.01" value={valorParcial} onChange={(e) => setValorParcial(e.target.value)} autoFocus /><p className="text-xs text-ink-muted">O restante ({parcialValido ? formatarMoeda(Math.round((acao.l.valor - vParcial) * 100) / 100) : '…'}) continua previsto com o mesmo vencimento.</p></>}
            {acao.tipo === 'cancelar' && <Campo rotulo="Motivo (opcional)" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={200} />}
            <div className="flex justify-end gap-2"><Botao variante="secundario" onClick={fechar}>Voltar</Botao><Botao variante={acao.tipo === 'cancelar' ? 'perigo' : 'primario'} onClick={confirmar} carregando={ocupado} disabled={acao.tipo === 'parcial' && !parcialValido}>Confirmar</Botao></div>
          </div>
        )}
      </Modal>
    </>
  )
}
export const ContasReceberPage = () => <ContasPage tipo="receita" />
export const ContasPagarPage = () => <ContasPage tipo="despesa" />
