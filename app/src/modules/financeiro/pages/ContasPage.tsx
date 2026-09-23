import { useMemo, useState } from 'react'
import { Link } from 'react-router'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { BarraFiltros, CampoBusca, ContagemFiltro, SelectFiltro } from '../../../core/ui/Filtros'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { SeletorMes } from '../../../core/ui/SeletorMes'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda, hojeISO, mesAtualISO } from '../../../core/formatos'
import { usePeriodo } from '../../../core/periodo/usePeriodo'
import { usePessoas } from '../../pessoas/api'
import { useContas } from '../../contas/api'
import { useContratos } from '../../contratos/api'
import { useCategorias } from '../../categorias/api'
import { useNegocios } from '../../negocios/api'
import { ROTULO_PESSOAL } from '../../negocios/tipos'
import { codigoContrato } from '../../contratos/tipos'
import { useBaixaParcial, useCancelarLancamento, useCriarLancamento, useEfetivarLancamento, useLancamentos, useLancamentosVencidosAntes } from '../../lancamentos/api'
import { ROTULO_PERIODICIDADE, rotuloParcela, type Lancamento } from '../../lancamentos/tipos'
import { useCartoesConfig } from '../../cartoes/api'
import { vencimentoFaturaReal } from '../../cartoes/tipos'
import { useCancelarConfianca, useConfiancasAtivas, useDarConfianca, type Confianca } from '../confiancas'

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

/** Linha de fatura de cartão: agrupa visualmente os lançamentos do mesmo vencimento, sem fundir nada no banco.
 *  Expande para mostrar cada compra com sua categoria; cada uma mantém as ações normais (pagar/baixa/cancelar/editar). */
function FaturaGrupo({ conta, vencimento, itens, total, aberta, todasPagas, aoAlternar, contratoPorId, nomePessoa, nomeCategoria, aoAgir, aoAjustar }: {
  conta: { nome: string } | undefined; vencimento: string; itens: Lancamento[]; total: number; aberta: boolean; todasPagas: boolean
  aoAlternar: () => void; contratoPorId: Map<string, { codigo: number }>; nomePessoa: Map<string, string>; nomeCategoria: Map<string, string>
  aoAgir: (l: Lancamento, tipo: 'baixa' | 'parcial' | 'cancelar') => void; aoAjustar: () => void
}) {
  return (
    <>
      <tr className="border-b border-line bg-canvas/60 hover:bg-canvas">
        <td className="whitespace-nowrap px-4 py-3 tabular-nums">{formatarData(vencimento)}</td>
        <td className="px-4 py-3" colSpan={2}>
          <button type="button" onClick={aoAlternar} className="flex items-center gap-2 text-left font-medium hover:underline">
            <span className="text-ink-muted">{aberta ? '▾' : '▸'}</span>
            Fatura {conta?.nome ?? 'Cartão'} <span className="font-normal text-ink-muted">· {itens.length} item(ns)</span>
          </button>
        </td>
        <td className="whitespace-nowrap px-4 py-3 text-right font-medium tabular-nums">{formatarMoeda(total)}</td>
        <td className="whitespace-nowrap px-4 py-3"><Distintivo tom={todasPagas ? 'ok' : 'info'}>{todasPagas ? 'Pago' : 'Em aberto'}</Distintivo></td>
        <td className="whitespace-nowrap px-4 py-3 text-right"><button type="button" className="text-brand-700 hover:underline" onClick={aoAjustar}>+ Ajuste</button></td>
      </tr>
      {aberta && itens.map((l) => {
        const st = situacaoDe(l); const c = l.contrato_id ? contratoPorId.get(l.contrato_id) : undefined
        return (
          <tr key={l.id} className="border-b border-line bg-canvas/30 text-xs last:border-0 hover:bg-surface">
            <td className="whitespace-nowrap px-4 py-2 pl-8 tabular-nums text-ink-muted">{formatarData(l.data_competencia)}</td>
            <td className="px-4 py-2">
              <span className="font-medium">{l.descricao}</span>{c && <span className="ml-2 font-mono text-ink-muted">{codigoContrato(c)}</span>}
              {l.recorrente && <span className="ml-2 text-ink-muted">🔄 {rotuloParcela(l)}</span>}
              {l.categoria_id && <span className="ml-2 text-ink-muted">{nomeCategoria.get(l.categoria_id) ?? ''}</span>}
            </td>
            <td className="whitespace-nowrap px-4 py-2">{l.pessoa_id ? nomePessoa.get(l.pessoa_id) ?? '—' : '—'}</td>
            <td className="whitespace-nowrap px-4 py-2 text-right tabular-nums">{formatarMoeda(l.valor)}</td>
            <td className="whitespace-nowrap px-4 py-2"><Distintivo tom={TOM[st]}>{st === 'pago' ? 'Pago' : ROTULO[st]}</Distintivo></td>
            <td className="whitespace-nowrap px-4 py-2 text-right">
              <Link to={`/financeiro/lancamentos?editar=${l.id}`} className="text-brand-700 hover:underline">Editar</Link>
              {l.status === 'previsto' && <><button type="button" className="ml-2 text-brand-700 hover:underline" onClick={() => aoAgir(l, 'baixa')}>Pagar</button><button type="button" className="ml-2 text-brand-700 hover:underline" onClick={() => aoAgir(l, 'parcial')}>Baixa parcial</button><button type="button" className="ml-2 text-ink-muted hover:underline" onClick={() => aoAgir(l, 'cancelar')}>Cancelar</button></>}
            </td>
          </tr>
        )
      })}
    </>
  )
}

/** Contas a receber (receitas) e contas a pagar (despesas) do mês: previsto × realizado, filtros e baixas. */
function ContasPage({ tipo }: { tipo: 'receita' | 'despesa' }) {
  const receber = tipo === 'receita'
  const { mes, setMes } = usePeriodo()
  const lancamentos = useLancamentos(mes); const pessoas = usePessoas(); const contratos = useContratos(); const contas = useContas()
  const efetivar = useEfetivarLancamento(); const parcial = useBaixaParcial(); const cancelar = useCancelarLancamento()
  const negocios = useNegocios()
  const [filtroPessoa, setFiltroPessoa] = useState(''); const [filtroSituacao, setFiltroSituacao] = useState<Situacao | ''>(''); const [busca, setBusca] = useState('')
  const [filtroNegocio, setFiltroNegocio] = useState('') // '' = todos, 'pessoal' = sem negócio, ou o id
  const [filtroCategoria, setFiltroCategoria] = useState(''); const [filtroConta, setFiltroConta] = useState(''); const [filtroAtraso, setFiltroAtraso] = useState('')
  const [acao, setAcao] = useState<Acao>(null); const [dataBaixa, setDataBaixa] = useState(hojeISO()); const [valorParcial, setValorParcial] = useState(''); const [motivo, setMotivo] = useState(''); const [encargos, setEncargos] = useState(''); const [contaBaixa, setContaBaixa] = useState('')
  const categorias = useCategorias()
  const criarAjuste = useCriarLancamento()
  // promessa de pagamento (voto de confiança): só faz sentido em contas a receber
  const confiancas = useConfiancasAtivas(receber)
  const darConfianca = useDarConfianca()
  const cancelarConfianca = useCancelarConfianca()
  const confiancaPorContrato = useMemo(() => new Map((confiancas.data ?? []).map((c) => [c.contrato_id, c])), [confiancas.data])
  const [promessa, setPromessa] = useState<{ l: Lancamento; atual: Confianca | undefined } | null>(null)
  const [promessaAte, setPromessaAte] = useState(''); const [promessaObs, setPromessaObs] = useState('')
  const promessaDe = (l: Lancamento) => (receber && l.contrato_id ? confiancaPorContrato.get(l.contrato_id) : undefined)
  function abrirPromessa(l: Lancamento) {
    const atual = l.contrato_id ? confiancaPorContrato.get(l.contrato_id) : undefined
    setPromessaAte(atual?.segurar_ate ?? ''); setPromessaObs(atual?.observacao ?? '')
    darConfianca.reset(); cancelarConfianca.reset()
    setPromessa({ l, atual })
  }
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const contratoPorId = useMemo(() => new Map((contratos.data ?? []).map((c) => [c.id, c])), [contratos.data])
  const contaPorId = useMemo(() => new Map((contas.data ?? []).map((c) => [c.id, c])), [contas.data])
  const nomeCategoria = useMemo(() => new Map((categorias.data ?? []).map((c) => [c.id, c.nome])), [categorias.data])
  const cartoesConfig = useCartoesConfig()
  /** Contexto do lançamento no modal de baixa: parcela, recorrência, fatura do cartão e rastro de baixa parcial. */
  function contextoLancamento(l: Lancamento) {
    const conta = contaPorId.get(l.conta_id)
    const cfg = conta?.tipo === 'credito' ? (cartoesConfig.data ?? []).find((k) => k.conta_id === conta.id) : undefined
    const partes: string[] = []
    const parcela = rotuloParcela(l)
    if (parcela === 'Fixo') partes.push(`🔄 Recorrente ${l.periodicidade ? ROTULO_PERIODICIDADE[l.periodicidade].toLowerCase() : ''}`.trim())
    else if (parcela) partes.push(`🔄 ${parcela}${l.periodicidade ? ` · ${ROTULO_PERIODICIDADE[l.periodicidade].toLowerCase()}` : ''}`)
    else partes.push('Pagamento único (não parcelado)')
    if (conta) partes.push(conta.tipo === 'credito' ? `💳 ${conta.nome}${cfg ? ` · fatura vence ${formatarData(vencimentoFaturaReal(l.data_competencia, cfg))}` : ''}` : conta.nome)
    if (l.categoria_id) partes.push(nomeCategoria.get(l.categoria_id) ?? '')
    return partes.filter(Boolean)
  }
  const [faturasAbertas, setFaturasAbertas] = useState<Set<string>>(new Set())
  const [faturaAjuste, setFaturaAjuste] = useState<{ contaId: string; vencimento: string; negocioId: string | null } | null>(null)
  const [ajusteDescricao, setAjusteDescricao] = useState(''); const [ajusteValor, setAjusteValor] = useState(''); const [ajusteCategoriaId, setAjusteCategoriaId] = useState('')
  // cortesia (0080): fatura cancelada com motivo 'Cortesia' aparece na lista, mas fica fora dos totais
  const ehCortesia = (l: Lancamento) => l.status === 'cancelado' && l.motivo_cancelamento === 'Cortesia'
  // o filtro de negócio entra já na base: os indicadores do topo (previsto, realizado, vencidos)
  // passam a valer para o negócio escolhido, não só a lista
  const base = (lancamentos.data ?? [])
    .filter((l) => l.tipo === tipo && (l.status !== 'cancelado' || ehCortesia(l)))
    .filter((l) => !filtroNegocio || (filtroNegocio === 'pessoal' ? l.negocio_id === null : l.negocio_id === filtroNegocio))
  const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
  const termo = normalizar(busca.trim())
  // aging: dias de atraso de quem está vencido (30/60/90+), como no extrato de inadimplência
  const diasAtraso = (l: Lancamento) => Math.floor((Date.parse(hojeISO()) - Date.parse(l.data_vencimento)) / 86_400_000)
  const lista = base
    .filter((l) => (!filtroPessoa || l.pessoa_id === filtroPessoa) && (!filtroSituacao || (!ehCortesia(l) && situacaoDe(l) === filtroSituacao)))
    .filter((l) => !filtroCategoria || l.categoria_id === filtroCategoria)
    .filter((l) => !filtroConta || l.conta_id === filtroConta)
    .filter((l) => {
      if (!filtroAtraso) return true
      if (situacaoDe(l) !== 'vencido' || ehCortesia(l)) return false
      const d = diasAtraso(l)
      return filtroAtraso === '30' ? d <= 30 : filtroAtraso === '60' ? d > 30 && d <= 60 : filtroAtraso === '90' ? d > 60 && d <= 90 : d > 90
    })
    .filter((l) => !termo || normalizar([l.descricao, l.pessoa_id ? nomePessoa.get(l.pessoa_id) : null, l.observacao].filter(Boolean).join(' ')).includes(termo))
    .sort((a, b) => a.data_vencimento.localeCompare(b.data_vencimento))
  // agrupamento visual por fatura de cartão (item 4 do levantamento): só na tela de despesas.
  // Só é uma "fatura" se houver 2+ lançamentos na mesma conta de crédito e vencimento — o normal
  // é ter várias parcelas/compras diferentes caindo no mesmo dia de vencimento da fatura.
  type LinhaFatura = { fatura: true; contaId: string; vencimento: string; itens: Lancamento[] }
  const gruposFatura = new Map<string, Lancamento[]>()
  if (!receber) {
    for (const l of lista) {
      if (contaPorId.get(l.conta_id)?.tipo !== 'credito') continue
      const chave = `${l.conta_id}|${l.data_vencimento}`
      const g = gruposFatura.get(chave); if (g) g.push(l); else gruposFatura.set(chave, [l])
    }
  }
  const emitidos = new Set<string>()
  const linhasExibidas: (Lancamento | LinhaFatura)[] = []
  for (const l of lista) {
    const conta = contaPorId.get(l.conta_id)
    if (!receber && conta?.tipo === 'credito') {
      const chave = `${l.conta_id}|${l.data_vencimento}`
      const itensGrupo = gruposFatura.get(chave) ?? [l]
      if (itensGrupo.length < 2) { linhasExibidas.push(l); continue } // compra avulsa no cartão: não vale a pena agrupar
      if (emitidos.has(chave)) continue
      emitidos.add(chave)
      linhasExibidas.push({ fatura: true, contaId: l.conta_id, vencimento: l.data_vencimento, itens: itensGrupo })
    } else {
      linhasExibidas.push(l)
    }
  }
  const previsto = base.filter((l) => l.status === 'previsto').reduce((s, l) => s + l.valor, 0)
  const realizado = base.filter((l) => l.status === 'efetivado').reduce((s, l) => s + l.valor, 0)
  const saldo = realizado - previsto
  const vencidos = base.filter((l) => !ehCortesia(l) && situacaoDe(l) === 'vencido')
  const pessoasComLanc = (pessoas.data ?? []).filter((p) => base.some((l) => l.pessoa_id === p.id))
  const erro = efetivar.error ?? parcial.error ?? cancelar.error
  const ocupado = efetivar.isPending || parcial.isPending || cancelar.isPending
  function fechar() { efetivar.reset(); parcial.reset(); cancelar.reset(); setAcao(null); setValorParcial(''); setMotivo(''); setDataBaixa(hojeISO()); setEncargos(''); setContaBaixa('') }
  // encargos derivados: valor pago informado − valor do lançamento
  const vPago = encargos.trim() === '' ? null : Math.round(Number(encargos.replace(',', '.')) * 100) / 100
  const vEncargos = acao && vPago !== null && !Number.isNaN(vPago) ? Math.round((vPago - acao.l.valor) * 100) / 100 : 0
  const pagoInsuficiente = acao?.tipo === 'baixa' && vPago !== null && (Number.isNaN(vPago) || vPago < acao.l.valor)
  function confirmar() {
    if (!acao) return
    if (acao.tipo === 'baixa') efetivar.mutate({ id: acao.l.id, data_efetivacao: dataBaixa, encargos: vEncargos > 0 ? vEncargos : undefined, conta_id: contaBaixa && contaBaixa !== acao.l.conta_id ? contaBaixa : undefined }, { onSuccess: fechar })
    if (acao.tipo === 'parcial') parcial.mutate({ id: acao.l.id, valor: Math.round(Number(valorParcial.replace(',', '.')) * 100) / 100, data_efetivacao: dataBaixa }, { onSuccess: fechar })
    if (acao.tipo === 'cancelar') cancelar.mutate({ id: acao.l.id, motivo }, { onSuccess: fechar })
  }
  const vParcial = Number(valorParcial.replace(',', '.'))
  const parcialValido = acao?.tipo === 'parcial' && vParcial > 0 && vParcial < acao.l.valor
  return (
    <>
      <CabecalhoPagina titulo={receber ? 'Contas a receber' : 'Contas a pagar'} descricao={receber ? 'Faturas e receitas do mês: previsto × realizado' : 'Compromissos com fornecedores: previsto × realizado'} />
      <div className="mb-4"><PendenciasAnteriores tipo={tipo} aoAbrirAcao={(l) => setAcao({ tipo: 'baixa', l })} /></div>
      <div className="flex flex-wrap items-center gap-2 border-b border-line bg-white px-4 py-3 text-sm sm:px-6">
        <CampoBusca valor={busca} aoMudar={setBusca} rotulo={receber ? 'Pesquisar cliente, login ou descrição…' : 'Pesquisar fornecedor ou descrição…'} className="max-w-none" />
        <ContagemFiltro visiveis={lista.length} total={base.length} singular="lançamento" plural="lançamentos" />
      </div>
      <BarraFiltros>
        <SeletorMes mes={mes} aoMudar={setMes} />
        {(negocios.data ?? []).length > 0 && (
          <SelectFiltro rotulo="Filtrar por negócio" valor={filtroNegocio} aoMudar={setFiltroNegocio}>
            <option value="">Todos os negócios</option>
            <option value="pessoal">{ROTULO_PESSOAL}</option>
            {(negocios.data ?? []).filter((n) => n.ativo).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
          </SelectFiltro>
        )}
        <SelectFiltro rotulo={receber ? 'Filtrar por cliente' : 'Filtrar por fornecedor'} valor={filtroPessoa} aoMudar={setFiltroPessoa}>
          <option value="">{receber ? 'Todos os clientes' : 'Todos os fornecedores'}</option>
          {pessoasComLanc.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
        </SelectFiltro>
        <SelectFiltro rotulo="Filtrar por situação" valor={filtroSituacao} aoMudar={(v) => setFiltroSituacao(v as Situacao | '')}>
          <option value="">Todas as situações</option><option value="aberto">Em aberto</option><option value="vencido">Vencidos</option><option value="pago">{receber ? 'Recebidos' : 'Pagos'}</option>
        </SelectFiltro>
        <SelectFiltro rotulo="Filtrar por categoria" valor={filtroCategoria} aoMudar={setFiltroCategoria}>
          <option value="">Todas as categorias</option>
          {(categorias.data ?? []).filter((c) => c.ativo && c.tipo === tipo).map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
        </SelectFiltro>
        <SelectFiltro rotulo="Filtrar por conta" valor={filtroConta} aoMudar={setFiltroConta}>
          <option value="">Todas as contas</option>
          {(contas.data ?? []).filter((c) => c.ativo).map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
        </SelectFiltro>
        <SelectFiltro rotulo="Filtrar por dias de atraso" valor={filtroAtraso} aoMudar={setFiltroAtraso}>
          <option value="">Qualquer atraso</option>
          <option value="30">Vencidos até 30 dias</option>
          <option value="60">31 a 60 dias</option>
          <option value="90">61 a 90 dias</option>
          <option value="mais">Mais de 90 dias</option>
        </SelectFiltro>
      </BarraFiltros>
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
            <>
            {/* Mobile: cartão por linha (a tabela de 6 colunas não cabe em tela de celular) */}
            <ul className="divide-y divide-line sm:hidden">
              {linhasExibidas.map((x) => {
                if ('fatura' in x) {
                  const chave = `${x.contaId}|${x.vencimento}`
                  const aberta = faturasAbertas.has(chave)
                  const totalFatura = x.itens.reduce((s, i) => s + i.valor, 0)
                  const todasPagas = x.itens.every((i) => i.status === 'efetivado')
                  return (
                    <li key={chave} className="bg-canvas/60 px-4 py-3">
                      <button type="button" className="flex w-full items-start justify-between gap-3 text-left"
                        onClick={() => setFaturasAbertas((s) => { const n = new Set(s); if (n.has(chave)) n.delete(chave); else n.add(chave); return n })}>
                        <span className="min-w-0 flex-1">
                          <span className="block text-xs tabular-nums text-ink-muted">{formatarData(x.vencimento)}</span>
                          <span className="mt-0.5 block font-medium">{aberta ? '▾' : '▸'} Fatura {contaPorId.get(x.contaId)?.nome ?? 'Cartão'}</span>
                          <span className="text-xs text-ink-muted">{x.itens.length} item(ns)</span>
                        </span>
                        <span className="shrink-0 text-right font-medium tabular-nums">{formatarMoeda(totalFatura)}</span>
                      </button>
                      <p className="mt-1.5 flex flex-wrap items-center gap-2">
                        <Distintivo tom={todasPagas ? 'ok' : 'info'}>{todasPagas ? 'Pago' : 'Em aberto'}</Distintivo>
                        <button type="button" className="text-xs text-brand-700 hover:underline"
                          onClick={() => { setAjusteDescricao(''); setAjusteValor(''); setAjusteCategoriaId(''); criarAjuste.reset(); setFaturaAjuste({ contaId: x.contaId, vencimento: x.vencimento, negocioId: x.itens[0]?.negocio_id ?? null }) }}>+ Ajuste</button>
                      </p>
                      {aberta && (
                        <ul className="mt-2 space-y-2 border-l-2 border-line pl-3">
                          {x.itens.map((l) => {
                            const st = situacaoDe(l)
                            return (
                              <li key={l.id} className="text-xs">
                                <span className="flex items-start justify-between gap-2">
                                  <span className="min-w-0 flex-1 font-medium">{l.descricao}</span>
                                  <span className="shrink-0 tabular-nums">{formatarMoeda(l.valor)}</span>
                                </span>
                                <span className="mt-0.5 block text-ink-muted">{formatarData(l.data_competencia)}{l.categoria_id ? ` · ${nomeCategoria.get(l.categoria_id) ?? ''}` : ''}{l.recorrente ? ` · 🔄 ${rotuloParcela(l)}` : ''}</span>
                                <span className="mt-1 flex flex-wrap items-center gap-2">
                                  <Distintivo tom={TOM[st]}>{st === 'pago' ? 'Pago' : ROTULO[st]}</Distintivo>
                                  <Link to={`/financeiro/lancamentos?editar=${l.id}`} className="text-brand-700 hover:underline">Editar</Link>
                                  {l.status === 'previsto' && <>
                                    <button type="button" className="text-brand-700 hover:underline" onClick={() => setAcao({ tipo: 'baixa', l })}>Pagar</button>
                                    <button type="button" className="text-brand-700 hover:underline" onClick={() => setAcao({ tipo: 'parcial', l })}>Parcial</button>
                                    <button type="button" className="text-ink-muted hover:underline" onClick={() => setAcao({ tipo: 'cancelar', l })}>Cancelar</button>
                                  </>}
                                </span>
                              </li>
                            )
                          })}
                        </ul>
                      )}
                    </li>
                  )
                }
                const l = x; const st = situacaoDe(l); const c = l.contrato_id ? contratoPorId.get(l.contrato_id) : undefined
                return (
                  <li key={l.id} className="px-4 py-3">
                    <div className="flex items-start justify-between gap-3">
                      <span className="min-w-0 flex-1">
                        <span className="block text-xs tabular-nums text-ink-muted">{formatarData(l.data_vencimento)}{l.pessoa_id ? ` · ${nomePessoa.get(l.pessoa_id) ?? '—'}` : ''}</span>
                        <span className="mt-0.5 block font-medium">{l.descricao}</span>
                        {(c || l.recorrente) && <span className="text-xs text-ink-muted">{c ? codigoContrato(c) : ''}{c && l.recorrente ? ' · ' : ''}{l.recorrente ? `🔄 ${rotuloParcela(l)}` : ''}</span>}
                        {l.observacao && <span className="block text-xs text-ink-muted">{l.observacao}</span>}
                      </span>
                      <span className="shrink-0 text-right font-medium tabular-nums">{ehCortesia(l) ? <span className="text-ink-muted line-through">{formatarMoeda(l.valor)}</span> : formatarMoeda(l.valor)}</span>
                    </div>
                    <p className="mt-1.5 flex flex-wrap items-center gap-2 text-xs">
                      {ehCortesia(l) ? <Distintivo tom="info">Cortesia</Distintivo> : <Distintivo tom={TOM[st]}>{st === 'pago' ? (receber ? 'Recebido' : 'Pago') : ROTULO[st]}</Distintivo>}
                      {l.data_efetivacao && <span className="text-ink-muted">{formatarData(l.data_efetivacao)}</span>}
                      {promessaDe(l) && <Distintivo tom="info">{`🤝 Paga até ${formatarData(promessaDe(l)!.segurar_ate)}`}</Distintivo>}
                      {l.status === 'previsto' && <>
                        <button type="button" className="text-brand-700 hover:underline" onClick={() => setAcao({ tipo: 'baixa', l })}>{receber ? 'Receber' : 'Pagar'}</button>
                        <button type="button" className="text-brand-700 hover:underline" onClick={() => setAcao({ tipo: 'parcial', l })}>Baixa parcial</button>
                        {receber && l.contrato_id && <button type="button" className="text-brand-700 hover:underline" onClick={() => abrirPromessa(l)}>🤝 Promessa</button>}
                        <button type="button" className="text-ink-muted hover:underline" onClick={() => setAcao({ tipo: 'cancelar', l })}>Cancelar</button>
                      </>}
                    </p>
                  </li>
                )
              })}
            </ul>
            {/* Desktop: tabela completa */}
            <div className="hidden overflow-x-auto sm:block"><table className="w-full text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="whitespace-nowrap px-4 py-3 font-medium">Vencimento</th><th className="w-full px-4 py-3 font-medium">Descrição</th><th className="whitespace-nowrap px-4 py-3 font-medium">{receber ? 'Cliente' : 'Fornecedor'}</th><th className="whitespace-nowrap px-4 py-3 text-right font-medium">Valor</th><th className="whitespace-nowrap px-4 py-3 font-medium">Situação</th><th className="px-4 py-3"></th></tr></thead>
              <tbody>{linhasExibidas.map((x) => {
                if ('fatura' in x) {
                  const chave = `${x.contaId}|${x.vencimento}`
                  const aberta = faturasAbertas.has(chave)
                  const totalFatura = x.itens.reduce((s, i) => s + i.valor, 0)
                  const todasPagas = x.itens.every((i) => i.status === 'efetivado')
                  return (
                    <FaturaGrupo key={chave} conta={contaPorId.get(x.contaId)} vencimento={x.vencimento} itens={x.itens} total={totalFatura}
                      aberta={aberta} todasPagas={todasPagas}
                      aoAlternar={() => setFaturasAbertas((s) => { const n = new Set(s); if (n.has(chave)) n.delete(chave); else n.add(chave); return n })}
                      contratoPorId={contratoPorId} nomePessoa={nomePessoa} nomeCategoria={nomeCategoria}
                      aoAgir={(l, tipoAcao) => setAcao({ tipo: tipoAcao, l })}
                      aoAjustar={() => { setAjusteDescricao(''); setAjusteValor(''); setAjusteCategoriaId(''); criarAjuste.reset(); setFaturaAjuste({ contaId: x.contaId, vencimento: x.vencimento, negocioId: x.itens[0]?.negocio_id ?? null }) }}
                    />
                  )
                }
                const l = x; const st = situacaoDe(l); const c = l.contrato_id ? contratoPorId.get(l.contrato_id) : undefined
                return (
                <tr key={l.id} className="border-b border-line last:border-0 hover:bg-surface">
                  <td className="whitespace-nowrap px-4 py-3 tabular-nums">{formatarData(l.data_vencimento)}</td>
                  <td className="px-4 py-3"><span className="font-medium">{l.descricao}</span>{c && <span className="ml-2 font-mono text-xs text-ink-muted">{codigoContrato(c)}</span>}{l.recorrente && <span className="ml-2 text-xs text-ink-muted">🔄 {rotuloParcela(l)}</span>}{l.observacao && <p className="text-xs text-ink-muted">{l.observacao}</p>}</td>
                  <td className="whitespace-nowrap px-4 py-3">{l.pessoa_id ? nomePessoa.get(l.pessoa_id) ?? '—' : '—'}</td>
                  <td className="whitespace-nowrap px-4 py-3 text-right font-medium tabular-nums">{ehCortesia(l) ? <span className="text-ink-muted line-through">{formatarMoeda(l.valor)}</span> : formatarMoeda(l.valor)}</td>
                  <td className="whitespace-nowrap px-4 py-3">
                    {ehCortesia(l) ? <Distintivo tom="info">Cortesia</Distintivo> : <Distintivo tom={TOM[st]}>{st === 'pago' ? (receber ? 'Recebido' : 'Pago') : ROTULO[st]}</Distintivo>}
                    {l.data_efetivacao && <span className="ml-1 text-xs text-ink-muted">{formatarData(l.data_efetivacao)}</span>}
                    {promessaDe(l) && <span className="ml-1" title={promessaDe(l)!.observacao ?? undefined}><Distintivo tom="info">{`🤝 Paga até ${formatarData(promessaDe(l)!.segurar_ate)}`}</Distintivo></span>}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3 text-right">{l.status === 'previsto' && <><button type="button" className="text-brand-700 hover:underline" onClick={() => setAcao({ tipo: 'baixa', l })}>{receber ? 'Receber' : 'Pagar'}</button><button type="button" className="ml-3 text-brand-700 hover:underline" onClick={() => setAcao({ tipo: 'parcial', l })}>Baixa parcial</button>{receber && l.contrato_id && <button type="button" className="ml-3 text-brand-700 hover:underline" onClick={() => abrirPromessa(l)}>🤝 Promessa</button>}<button type="button" className="ml-3 text-ink-muted hover:underline" onClick={() => setAcao({ tipo: 'cancelar', l })}>Cancelar</button></>}</td>
                </tr>) })}</tbody>
            </table></div>
            </>
          )}
        </Cartao>
      )}
      <Modal aberto={acao !== null} aoFechar={fechar} largura="md" titulo={acao?.tipo === 'baixa' ? (receber ? 'Marcar como recebido' : 'Marcar como pago') : acao?.tipo === 'parcial' ? 'Baixa parcial' : 'Cancelar lançamento'}>
        {acao && (
          <div className="space-y-4">
            {erro && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}
            <div className="rounded-md border border-line bg-surface/60 p-3">
              <p className="text-sm"><span className="font-medium">{acao.l.descricao}</span> · {formatarMoeda(acao.l.valor)} · vence {formatarData(acao.l.data_vencimento)}</p>
              <p className="mt-1 text-xs text-ink-muted">{contextoLancamento(acao.l).join(' · ')}</p>
              {acao.l.observacao && <p className="mt-1 text-xs text-ink-muted">📝 {acao.l.observacao}</p>}
              {contaPorId.get(acao.l.conta_id)?.tipo === 'credito' && acao.tipo === 'baixa' && (
                <p className="mt-1 text-xs text-amber-800">Compra no cartão: o normal é ela ser baixada sozinha no fechamento da fatura, e você pagar a fatura em Cartões. Só marque como paga aqui se tiver pago essa compra por fora.</p>
              )}
            </div>
            {acao.tipo !== 'cancelar' && <Campo rotulo={receber ? 'Data do recebimento' : 'Data do pagamento'} type="date" value={dataBaixa} onChange={(e) => setDataBaixa(e.target.value)} />}
            {acao.tipo === 'baixa' && acao.l.tipo !== 'transferencia' && (
              <div className="space-y-1">
                <label htmlFor="conta-baixa" className="block text-sm font-medium text-ink">{receber ? 'Conta do recebimento' : 'Conta do pagamento'}</label>
                <select id="conta-baixa" value={contaBaixa || acao.l.conta_id} onChange={(e) => setContaBaixa(e.target.value)} className="h-10 w-full rounded-md border border-line bg-white px-3 text-sm outline-none focus:border-brand-600">
                  {(contas.data ?? []).filter((c) => (c.ativo && c.tipo !== 'credito') || c.id === acao.l.conta_id).map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
                </select>
              </div>
            )}
            {acao.tipo === 'baixa' && dataBaixa > acao.l.data_vencimento && (
              <>
                <Campo rotulo={`Valor ${receber ? 'recebido' : 'pago'} com encargos (R$, opcional)`} type="number" step="0.01" min="0" value={encargos} onChange={(e) => setEncargos(e.target.value)} placeholder={String(acao.l.valor)} />
                {pagoInsuficiente
                  ? <p className="text-xs text-red-600">Menor que o valor do lançamento ({formatarMoeda(acao.l.valor)}). Para pagamento menor, use "Baixa parcial".</p>
                  : <p className="text-xs text-ink-muted">{vEncargos > 0 ? <>Encargos por atraso: <b>{formatarMoeda(vEncargos)}</b> (diferença sobre {formatarMoeda(acao.l.valor)}). Entram só nesta parcela e ficam na observação.</> : `Vazio ou igual ao valor = sem encargos.`}</p>}
              </>
            )}
            {acao.tipo === 'parcial' && <><Campo rotulo={receber ? 'Valor recebido (R$)' : 'Valor pago (R$)'} type="number" step="0.01" min="0.01" value={valorParcial} onChange={(e) => setValorParcial(e.target.value)} autoFocus /><p className="text-xs text-ink-muted">O restante ({parcialValido ? formatarMoeda(Math.round((acao.l.valor - vParcial) * 100) / 100) : '…'}) continua previsto com o mesmo vencimento.</p></>}
            {acao.tipo === 'cancelar' && <Campo rotulo="Motivo (opcional)" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={200} />}
            <div className="flex justify-end gap-2"><Botao variante="secundario" onClick={fechar}>Voltar</Botao><Botao variante={acao.tipo === 'cancelar' ? 'perigo' : 'primario'} onClick={confirmar} carregando={ocupado} disabled={(acao.tipo === 'parcial' && !parcialValido) || pagoInsuficiente}>Confirmar</Botao></div>
          </div>
        )}
      </Modal>
      <Modal aberto={promessa !== null} aoFechar={() => setPromessa(null)} largura="md" titulo="Promessa de pagamento">
        {promessa && (
          <div className="space-y-4">
            {(darConfianca.error ?? cancelarConfianca.error) && <Alerta tipo="erro">{mensagemDeErro(darConfianca.error ?? cancelarConfianca.error)}</Alerta>}
            <p className="text-sm"><span className="font-medium">{promessa.l.pessoa_id ? nomePessoa.get(promessa.l.pessoa_id) ?? '—' : '—'}</span> · {formatarMoeda(promessa.l.valor)} · vence {formatarData(promessa.l.data_vencimento)}</p>
            <p className="text-xs text-ink-muted">O cliente prometeu pagar até a data? O bloqueio fica segurado até lá e a promessa aparece nesta tela e na Cobrança. Pagou no prazo → confiança cumprida; passou devendo → volta destacado como <b>confiança furada</b>.</p>
            <Campo rotulo="Pagar até" type="date" value={promessaAte} min={new Date(Date.now() + 86400000).toISOString().slice(0, 10)} onChange={(e) => setPromessaAte(e.target.value)} />
            <Campo rotulo="Combinado (opcional)" value={promessaObs} onChange={(e) => setPromessaObs(e.target.value)} maxLength={200} placeholder="Ex.: falou que recebe dia 20" />
            <div className="flex flex-wrap justify-end gap-2">
              {promessa.atual && (
                <Botao variante="perigo" carregando={cancelarConfianca.isPending}
                  onClick={() => cancelarConfianca.mutate(promessa.atual!.id, { onSuccess: () => setPromessa(null) })}>Cancelar promessa</Botao>
              )}
              <Botao variante="secundario" onClick={() => setPromessa(null)}>Voltar</Botao>
              <Botao disabled={!promessaAte} carregando={darConfianca.isPending}
                onClick={() => promessa.l.contrato_id && darConfianca.mutate({ contratoId: promessa.l.contrato_id, segurarAte: promessaAte, observacao: promessaObs.trim() || null }, { onSuccess: () => setPromessa(null) })}>
                {promessa.atual ? 'Atualizar' : 'Registrar'}
              </Botao>
            </div>
          </div>
        )}
      </Modal>
      <Modal aberto={faturaAjuste !== null} aoFechar={() => setFaturaAjuste(null)} largura="md" titulo="Lançar ajuste na fatura">
        {faturaAjuste && (
          <div className="space-y-4">
            {criarAjuste.error && <Alerta tipo="erro">{mensagemDeErro(criarAjuste.error)}</Alerta>}
            <p className="text-xs text-ink-muted">Cria uma despesa própria com o mesmo vencimento desta fatura ({formatarData(faturaAjuste.vencimento)}) — entra no grupo, mas fica separada no Financeiro (anuidade, juros, estorno manual…).</p>
            <Campo rotulo="Descrição" value={ajusteDescricao} onChange={(e) => setAjusteDescricao(e.target.value)} maxLength={140} autoFocus />
            <Campo rotulo="Valor (R$)" type="number" step="0.01" min="0.01" value={ajusteValor} onChange={(e) => setAjusteValor(e.target.value)} />
            <Selecao rotulo="Categoria" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(categorias.data ?? []).filter((c) => c.tipo === 'despesa').map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={ajusteCategoriaId} onChange={(e) => setAjusteCategoriaId(e.target.value)} />
            <div className="flex justify-end gap-2">
              <Botao variante="secundario" onClick={() => setFaturaAjuste(null)}>Voltar</Botao>
              <Botao disabled={!ajusteDescricao.trim() || !(Number(ajusteValor.replace(',', '.')) > 0) || !ajusteCategoriaId} carregando={criarAjuste.isPending}
                onClick={() => criarAjuste.mutate({
                  tipo: 'despesa', descricao: ajusteDescricao.trim(), valor: Math.round(Number(ajusteValor.replace(',', '.')) * 100) / 100,
                  data_competencia: hojeISO(), data_vencimento: faturaAjuste.vencimento, data_efetivacao: null,
                  conta_id: faturaAjuste.contaId, conta_destino_id: null, categoria_id: ajusteCategoriaId, observacao: 'Ajuste de fatura',
                  negocio_id: faturaAjuste.negocioId, pessoa_id: null, contrato_id: null,
                  recorrente: false, periodicidade: null, numero_parcelas: null, parcela_inicial: null, data_fim_recorrencia: null,
                }, { onSuccess: () => setFaturaAjuste(null) })}>Lançar</Botao>
            </div>
          </div>
        )}
      </Modal>
    </>
  )
}
export const ContasReceberPage = () => <ContasPage tipo="receita" />
export const ContasPagarPage = () => <ContasPage tipo="despesa" />
