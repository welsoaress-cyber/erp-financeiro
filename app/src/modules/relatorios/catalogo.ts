/**
 * Catálogo da Central de Relatórios (etapa 53A). Um relatório = uma view
 * versionada no banco (security_invoker → RLS) + esta definição. Nada de SQL
 * dinâmico: a tela genérica só aplica filtros conhecidos e formata colunas.
 * Regra do projeto: toda etapa que cria dados registra aqui o relatório dela.
 */
export type TipoColuna = 'texto' | 'moeda' | 'data' | 'numero' | 'mes'
export type Filtro = 'mes' | 'periodo' | 'negocio' | 'centro' | 'pessoa' | 'categoria' | 'conta' | 'status' | 'tipo'
export type Area = 'Financeiro' | 'Clientes e contratos' | 'Operação' | 'Comercial'

export interface Coluna { chave: string; rotulo: string; tipo?: TipoColuna; totalizar?: boolean }
export type Linha = Record<string, unknown>

export interface Relatorio {
  id: string
  titulo: string
  area: Area
  descricao: string
  view: string
  filtros: Filtro[]
  colunas: Coluna[]
  /** filtro aplicado sempre (ex.: só despesas) */
  fixo?: Record<string, string>
  /** coluna do banco usada pelo filtro de período/mês */
  campoData?: string
  /** colunas pelas quais o usuário pode agrupar (subtotais na tela) */
  agrupavel?: string[]
  /** ordenação inicial */
  ordem?: { chave: string; desc?: boolean }
  /** transforma as linhas da view nas linhas do relatório (agregações no navegador) */
  preparar?: (linhas: Linha[]) => Linha[]
}

const num = (v: unknown) => Number(v ?? 0)

/** Soma por chave, mantendo campos de identificação. */
function somar(linhas: Linha[], chave: (l: Linha) => string, base: (l: Linha) => Linha, acumular: (acc: Linha, l: Linha) => void): Linha[] {
  const mapa = new Map<string, Linha>()
  for (const l of linhas) {
    const k = chave(l)
    let acc = mapa.get(k)
    if (!acc) { acc = base(l); mapa.set(k, acc) }
    acumular(acc, l)
  }
  return [...mapa.values()]
}

const COLS_PREV_REAL: Coluna[] = [
  { chave: 'previsto', rotulo: 'Previsto', tipo: 'moeda', totalizar: true },
  { chave: 'realizado', rotulo: 'Realizado', tipo: 'moeda', totalizar: true },
  { chave: 'total', rotulo: 'Total', tipo: 'moeda', totalizar: true },
]

function porStatus(acc: Linha, l: Linha, sinal = 1) {
  const v = num(l.valor) * sinal
  if (l.status === 'efetivado') acc.realizado = num(acc.realizado) + v
  else acc.previsto = num(acc.previsto) + v
  acc.total = num(acc.total) + v
}

export const RELATORIOS: Relatorio[] = [
  {
    id: 'centro-custo',
    titulo: 'Resultado por centro de custo',
    area: 'Financeiro',
    descricao: 'Receita, despesa operacional, investimento e resultado do mês, negócio a negócio (realizado).',
    view: 'vw_centro_custo_mensal',
    filtros: ['mes', 'negocio'],
    campoData: 'mes',
    colunas: [
      { chave: 'negocio', rotulo: 'Centro de custo' },
      { chave: 'receitas', rotulo: 'Receitas', tipo: 'moeda', totalizar: true },
      { chave: 'operacional', rotulo: 'Desp. operacionais', tipo: 'moeda', totalizar: true },
      { chave: 'resultado_operacional', rotulo: 'Resultado operacional', tipo: 'moeda', totalizar: true },
      { chave: 'investimento', rotulo: 'Investimentos', tipo: 'moeda', totalizar: true },
      { chave: 'resultado', rotulo: 'Resultado', tipo: 'moeda', totalizar: true },
      { chave: 'previsto', rotulo: 'Ainda previsto (líq.)', tipo: 'moeda', totalizar: true },
    ],
    ordem: { chave: 'resultado', desc: true },
    preparar: (linhas) => somar(linhas,
      (l) => String(l.negocio_id ?? 'pessoal'),
      (l) => ({ negocio_id: l.negocio_id, negocio: l.negocio ?? 'Pessoal', receitas: 0, operacional: 0, investimento: 0, resultado_operacional: 0, resultado: 0, previsto: 0 }),
      (acc, l) => {
        const v = num(l.valor); const rec = l.tipo === 'receita'
        if (l.status !== 'efetivado') { acc.previsto = num(acc.previsto) + (rec ? v : -v); return }
        if (rec) acc.receitas = num(acc.receitas) + v
        else if (l.natureza === 'investimento') acc.investimento = num(acc.investimento) + v
        else acc.operacional = num(acc.operacional) + v
        acc.resultado_operacional = num(acc.receitas) - num(acc.operacional)
        acc.resultado = num(acc.resultado_operacional) - num(acc.investimento)
      }),
  },
  {
    id: 'dre',
    titulo: 'DRE simplificado',
    area: 'Financeiro',
    descricao: 'Receitas − despesas operacionais = resultado operacional; − investimentos = resultado do mês. Previsto × realizado.',
    view: 'vw_centro_custo_mensal',
    filtros: ['mes', 'negocio'],
    campoData: 'mes',
    colunas: [{ chave: 'linha', rotulo: 'Linha' }, ...COLS_PREV_REAL.map((c) => ({ ...c, totalizar: false }))],
    preparar: (linhas) => {
      const z = () => ({ previsto: 0, realizado: 0, total: 0 })
      const rec = z(), op = z(), inv = z()
      for (const l of linhas) {
        const alvo = l.tipo === 'receita' ? rec : l.natureza === 'investimento' ? inv : op
        porStatus(alvo as Linha, l)
      }
      const sub = (a: Linha, b: Linha, s = -1) => ({ previsto: num(a.previsto) + s * num(b.previsto), realizado: num(a.realizado) + s * num(b.realizado), total: num(a.total) + s * num(b.total) })
      const resOp = sub(rec, op); const res = sub(resOp, inv)
      return [
        { linha: 'Receitas', ...rec },
        { linha: '(−) Despesas operacionais', ...op },
        { linha: '= Resultado operacional', ...resOp, destaque: true },
        { linha: '(−) Investimentos (ativos)', ...inv },
        { linha: '= Resultado do mês', ...res, destaque: true },
      ]
    },
  },
  {
    id: 'despesas-categoria',
    titulo: 'Despesas por categoria',
    area: 'Financeiro',
    descricao: 'Quanto foi para cada categoria no mês, com natureza (operacional × investimento).',
    view: 'vw_centro_custo_mensal',
    filtros: ['mes', 'negocio'],
    fixo: { tipo: 'despesa' },
    campoData: 'mes',
    colunas: [
      { chave: 'categoria', rotulo: 'Categoria' },
      { chave: 'natureza', rotulo: 'Natureza' },
      { chave: 'negocio', rotulo: 'Centro de custo' },
      ...COLS_PREV_REAL,
    ],
    agrupavel: ['negocio', 'natureza'],
    ordem: { chave: 'total', desc: true },
    preparar: (linhas) => somar(linhas,
      (l) => `${l.categoria_id}|${l.negocio_id}`,
      (l) => ({ categoria: l.categoria, natureza: l.natureza, negocio: l.negocio ?? 'Pessoal', previsto: 0, realizado: 0, total: 0 }),
      (acc, l) => porStatus(acc, l)),
  },
  {
    id: 'lancamentos',
    titulo: 'Lançamentos',
    area: 'Financeiro',
    descricao: 'Listagem detalhada por período, com todos os filtros. Exporta para conferência ou contador.',
    view: 'vw_rel_lancamentos',
    filtros: ['periodo', 'tipo', 'status', 'negocio', 'centro', 'pessoa', 'categoria', 'conta'],
    campoData: 'data_competencia',
    colunas: [
      { chave: 'data_competencia', rotulo: 'Competência', tipo: 'data' },
      { chave: 'data_vencimento', rotulo: 'Vencimento', tipo: 'data' },
      { chave: 'data_efetivacao', rotulo: 'Efetivado em', tipo: 'data' },
      { chave: 'descricao', rotulo: 'Descrição' },
      { chave: 'tipo', rotulo: 'Tipo' },
      { chave: 'status', rotulo: 'Status' },
      { chave: 'valor', rotulo: 'Valor', tipo: 'moeda', totalizar: true },
      { chave: 'conta', rotulo: 'Conta' },
      { chave: 'categoria', rotulo: 'Categoria' },
      { chave: 'negocio', rotulo: 'Negócio' },
      { chave: 'centro_custo', rotulo: 'Centro de custo' },
      { chave: 'pessoa', rotulo: 'Pessoa' },
      { chave: 'contrato_codigo', rotulo: 'Contrato', tipo: 'numero' },
    ],
    agrupavel: ['negocio', 'centro_custo', 'categoria', 'pessoa', 'conta', 'tipo', 'status'],
    ordem: { chave: 'data_competencia' },
  },
  {
    id: 'contas-receber',
    titulo: 'Contas a receber — previsto × realizado',
    area: 'Financeiro',
    descricao: 'Por cliente no mês: o que estava previsto, o que já entrou e o total.',
    view: 'vw_rel_lancamentos',
    filtros: ['mes', 'negocio', 'pessoa'],
    fixo: { tipo: 'receita' },
    campoData: 'data_competencia',
    colunas: [{ chave: 'pessoa', rotulo: 'Cliente' }, { chave: 'negocio', rotulo: 'Centro de custo' }, { chave: 'itens', rotulo: 'Faturas', tipo: 'numero' }, ...COLS_PREV_REAL],
    agrupavel: ['negocio'],
    ordem: { chave: 'total', desc: true },
    preparar: (linhas) => somar(linhas.filter((l) => l.status !== 'cancelado'),
      (l) => `${l.pessoa_id}|${l.negocio_id}`,
      (l) => ({ pessoa: l.pessoa ?? '(sem pessoa)', negocio: l.negocio, itens: 0, previsto: 0, realizado: 0, total: 0 }),
      (acc, l) => { acc.itens = num(acc.itens) + 1; porStatus(acc, l) }),
  },
  {
    id: 'contas-pagar',
    titulo: 'Contas a pagar — previsto × realizado',
    area: 'Financeiro',
    descricao: 'Por fornecedor/categoria no mês: previsto, pago e total.',
    view: 'vw_rel_lancamentos',
    filtros: ['mes', 'negocio', 'centro', 'pessoa', 'categoria'],
    fixo: { tipo: 'despesa' },
    campoData: 'data_competencia',
    colunas: [{ chave: 'pessoa', rotulo: 'Fornecedor' }, { chave: 'categoria', rotulo: 'Categoria' }, { chave: 'negocio', rotulo: 'Negócio' }, { chave: 'centro_custo', rotulo: 'Centro de custo' }, { chave: 'itens', rotulo: 'Itens', tipo: 'numero' }, ...COLS_PREV_REAL],
    agrupavel: ['negocio', 'centro_custo', 'categoria'],
    ordem: { chave: 'total', desc: true },
    preparar: (linhas) => somar(linhas.filter((l) => l.status !== 'cancelado'),
      (l) => `${l.pessoa_id}|${l.categoria_id}|${l.negocio_id}|${l.centro_custo_id}`,
      (l) => ({ pessoa: l.pessoa ?? '(sem fornecedor)', categoria: l.categoria ?? '(sem categoria)', negocio: l.negocio, centro_custo: l.centro_custo ?? 'Geral', itens: 0, previsto: 0, realizado: 0, total: 0 }),
      (acc, l) => { acc.itens = num(acc.itens) + 1; porStatus(acc, l) }),
  },
  {
    id: 'gastos-centro-custo',
    titulo: 'Gastos por centro de custo',
    area: 'Financeiro',
    descricao: 'Quanto cada departamento, projeto ou ponto de rede gastou no mês (previsto × realizado). Sem centro = Geral.',
    view: 'vw_rel_gastos_centro_custo',
    filtros: ['mes', 'negocio', 'centro'],
    campoData: 'mes',
    colunas: [
      { chave: 'centro_custo', rotulo: 'Centro de custo' },
      { chave: 'tipo_centro', rotulo: 'Tipo' },
      { chave: 'negocio', rotulo: 'Negócio' },
      { chave: 'operacional', rotulo: 'Operacional', tipo: 'moeda', totalizar: true },
      { chave: 'investimento', rotulo: 'Investimento', tipo: 'moeda', totalizar: true },
      ...COLS_PREV_REAL,
    ],
    agrupavel: ['negocio', 'tipo_centro'],
    ordem: { chave: 'total', desc: true },
    preparar: (linhas) => somar(linhas,
      (l) => `${l.centro_custo_id ?? 'geral'}|${l.negocio_id}`,
      (l) => ({ centro_custo_id: l.centro_custo_id, centro_custo: l.centro_custo, tipo_centro: l.tipo_centro ?? '—', negocio_id: l.negocio_id, negocio: l.negocio, operacional: 0, investimento: 0, previsto: 0, realizado: 0, total: 0 }),
      (acc, l) => {
        porStatus(acc, l)
        if (l.status === 'efetivado') { if (l.natureza === 'investimento') acc.investimento = num(acc.investimento) + num(l.valor); else acc.operacional = num(acc.operacional) + num(l.valor) }
      }),
  },
  {
    id: 'inadimplencia',
    titulo: 'Inadimplência',
    area: 'Financeiro',
    descricao: 'Faturas vencidas e em aberto hoje, com dias de atraso e telefone para cobrança.',
    view: 'vw_rel_inadimplencia',
    filtros: ['negocio', 'pessoa'],
    colunas: [
      { chave: 'pessoa', rotulo: 'Cliente' },
      { chave: 'telefone', rotulo: 'Telefone' },
      { chave: 'contrato_codigo', rotulo: 'Contrato', tipo: 'numero' },
      { chave: 'descricao', rotulo: 'Fatura' },
      { chave: 'data_vencimento', rotulo: 'Vencimento', tipo: 'data' },
      { chave: 'dias_atraso', rotulo: 'Dias', tipo: 'numero' },
      { chave: 'valor', rotulo: 'Valor', tipo: 'moeda', totalizar: true },
      { chave: 'negocio', rotulo: 'Centro de custo' },
    ],
    agrupavel: ['pessoa', 'negocio'],
    ordem: { chave: 'dias_atraso', desc: true },
  },
]

export const AREAS: Area[] = ['Financeiro', 'Clientes e contratos', 'Operação', 'Comercial']
export const relatorioPorId = (id: string) => RELATORIOS.find((r) => r.id === id)
