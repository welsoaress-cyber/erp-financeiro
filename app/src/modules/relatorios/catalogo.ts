/**
 * Catálogo da Central de Relatórios (etapa 53A). Um relatório = uma view
 * versionada no banco (security_invoker → RLS) + esta definição. Nada de SQL
 * dinâmico: a tela genérica só aplica filtros conhecidos e formata colunas.
 * Regra do projeto: toda etapa que cria dados registra aqui o relatório dela.
 */
export type TipoColuna = 'texto' | 'moeda' | 'custo' | 'data' | 'numero' | 'mes' // custo = moeda exibida como saída (− e vermelho)
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
    titulo: 'Resultado por negócio',
    area: 'Financeiro',
    descricao: 'Receita, despesa operacional, investimento e resultado do mês, negócio a negócio (realizado). Para departamentos/POPs use Gastos por centro de custo.',
    view: 'vw_centro_custo_mensal',
    filtros: ['mes', 'negocio'],
    campoData: 'mes',
    colunas: [
      { chave: 'negocio', rotulo: 'Negócio' },
      { chave: 'receitas', rotulo: 'Receitas', tipo: 'moeda', totalizar: true },
      { chave: 'operacional', rotulo: 'Desp. operacionais', tipo: 'custo', totalizar: true },
      { chave: 'resultado_operacional', rotulo: 'Resultado operacional', tipo: 'moeda', totalizar: true },
      { chave: 'investimento', rotulo: 'Investimentos', tipo: 'custo', totalizar: true },
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
      { chave: 'negocio', rotulo: 'Negócio' },
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
    colunas: [{ chave: 'pessoa', rotulo: 'Cliente' }, { chave: 'negocio', rotulo: 'Negócio' }, { chave: 'itens', rotulo: 'Faturas', tipo: 'numero' }, ...COLS_PREV_REAL],
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
      { chave: 'operacional', rotulo: 'Operacional', tipo: 'custo', totalizar: true },
      { chave: 'investimento', rotulo: 'Investimento', tipo: 'custo', totalizar: true },
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
    id: 'custo-cliente',
    titulo: 'Custo por cliente (contrato)',
    area: 'Clientes e contratos',
    descricao: 'Quanto cada cliente rendeu e custou: instalação, despesas lançadas para o contrato, resultado e payback.',
    view: 'vw_rel_custo_cliente',
    filtros: ['negocio', 'pessoa'],
    colunas: [
      { chave: 'pessoa', rotulo: 'Cliente' },
      { chave: 'contrato_codigo', rotulo: '#', tipo: 'numero' },
      { chave: 'plano', rotulo: 'Plano' },
      { chave: 'status', rotulo: 'Status' },
      { chave: 'receitas', rotulo: 'Recebido', tipo: 'moeda', totalizar: true },
      { chave: 'custo_total', rotulo: 'Custo', tipo: 'custo', totalizar: true },
      { chave: 'resultado', rotulo: 'Resultado', tipo: 'moeda', totalizar: true },
      { chave: 'payback_estimado_meses', rotulo: 'Payback (meses)', tipo: 'numero' },
      { chave: 'payback_real_meses', rotulo: 'Pagou em (meses)', tipo: 'numero' },
      { chave: 'custo_instalacao', rotulo: 'Instalação', tipo: 'custo', totalizar: true },
      { chave: 'despesas_contrato', rotulo: 'Despesas', tipo: 'custo', totalizar: true },
    ],
    agrupavel: ['negocio', 'plano', 'status'],
    ordem: { chave: 'resultado' },
  },
  {
    id: 'estoque-itens',
    titulo: 'Materiais em estoque',
    area: 'Operação',
    descricao: 'Lista de itens com saldo, custo médio, valor em estoque, mínimo, situação e o que está em comodato (quantidade e valor).',
    view: 'vw_rel_estoque_itens',
    filtros: ['negocio'],
    colunas: [
      { chave: 'item', rotulo: 'Item' },
      { chave: 'codigo', rotulo: 'Código' },
      { chave: 'categoria', rotulo: 'Categoria' },
      { chave: 'quantidade_atual', rotulo: 'Saldo', tipo: 'numero' },
      { chave: 'unidade_medida', rotulo: 'Un.' },
      { chave: 'custo_medio', rotulo: 'Custo médio', tipo: 'moeda' },
      { chave: 'valor_estoque', rotulo: 'Valor em estoque', tipo: 'moeda', totalizar: true },
      { chave: 'quantidade_minima', rotulo: 'Mínimo', tipo: 'numero' },
      { chave: 'em_comodato', rotulo: 'Em comodato', tipo: 'numero' },
      { chave: 'valor_comodato', rotulo: 'Valor em comodato', tipo: 'moeda', totalizar: true },
      { chave: 'situacao', rotulo: 'Situação' },
      { chave: 'localizacao', rotulo: 'Local' },
    ],
    agrupavel: ['categoria', 'situacao', 'negocio'],
    ordem: { chave: 'item' },
    preparar: (linhas) => linhas.filter((l) => l.ativo !== false),
  },
  {
    id: 'materiais-cliente',
    titulo: 'Materiais alocados em clientes',
    area: 'Operação',
    descricao: 'O que está na casa de cada cliente: equipamentos em comodato (série) e materiais baixados em instalação, com contrato.',
    view: 'vw_rel_materiais_cliente',
    filtros: ['negocio', 'pessoa'],
    colunas: [
      { chave: 'pessoa', rotulo: 'Cliente' },
      { chave: 'contrato_codigo', rotulo: '#', tipo: 'numero' },
      { chave: 'item', rotulo: 'Item' },
      { chave: 'numero_serie', rotulo: 'Série' },
      { chave: 'quantidade', rotulo: 'Qtd', tipo: 'numero' },
      { chave: 'tipo', rotulo: 'Tipo' },
      { chave: 'situacao', rotulo: 'Situação' },
      { chave: 'data', rotulo: 'Desde', tipo: 'data' },
      { chave: 'valor', rotulo: 'Valor', tipo: 'moeda', totalizar: true },
      { chave: 'telefone', rotulo: 'Telefone' },
    ],
    agrupavel: ['pessoa', 'item', 'tipo', 'situacao'],
    ordem: { chave: 'pessoa' },
  },
  {
    id: 'devolucoes-fornecedor',
    titulo: 'Devoluções ao fornecedor',
    area: 'Operação',
    descricao: 'Itens com defeito devolvidos: abertas (aguardando o fornecedor), reembolsadas, trocadas ou negadas.',
    view: 'vw_rel_devolucoes_fornecedor',
    filtros: ['negocio'],
    colunas: [
      { chave: 'item', rotulo: 'Item' },
      { chave: 'codigo', rotulo: 'Código' },
      { chave: 'quantidade', rotulo: 'Qtd', tipo: 'numero' },
      { chave: 'valor', rotulo: 'Valor', tipo: 'moeda', totalizar: true },
      { chave: 'motivo', rotulo: 'Motivo' },
      { chave: 'fornecedor', rotulo: 'Fornecedor' },
      { chave: 'situacao', rotulo: 'Situação' },
      { chave: 'data_envio', rotulo: 'Enviada em', tipo: 'data' },
      { chave: 'data_resolucao', rotulo: 'Resolvida em', tipo: 'data' },
    ],
    agrupavel: ['situacao', 'item', 'negocio'],
    ordem: { chave: 'data_envio' },
  },
  {
    id: 'compras-requisicoes-pendentes',
    titulo: 'Requisições de compra pendentes',
    area: 'Operação',
    descricao: 'Requisições aguardando sua aprovação, com quem pediu, quando e quantos itens.',
    view: 'vw_rel_compras_requisicoes_pendentes',
    filtros: ['negocio'],
    colunas: [
      { chave: 'numero', rotulo: 'Número', tipo: 'numero' },
      { chave: 'data', rotulo: 'Data', tipo: 'data' },
      { chave: 'negocio', rotulo: 'Negócio' },
      { chave: 'solicitante', rotulo: 'Solicitante' },
      { chave: 'justificativa', rotulo: 'Justificativa' },
      { chave: 'itens', rotulo: 'Itens', tipo: 'numero', totalizar: true },
      { chave: 'quantidade_total', rotulo: 'Qtd total', tipo: 'numero' },
    ],
    agrupavel: ['negocio', 'solicitante'],
    ordem: { chave: 'data' },
  },
  {
    id: 'compras-pedidos-abertos',
    titulo: 'Pedidos de compra em aberto',
    area: 'Operação',
    descricao: 'Pedidos aguardando recebimento (aberto ou recebido parcial), com fornecedor, previsão e valor.',
    view: 'vw_rel_compras_pedidos_abertos',
    filtros: ['negocio'],
    colunas: [
      { chave: 'numero', rotulo: 'Número', tipo: 'numero' },
      { chave: 'data_pedido', rotulo: 'Pedido', tipo: 'data' },
      { chave: 'negocio', rotulo: 'Negócio' },
      { chave: 'fornecedor', rotulo: 'Fornecedor' },
      { chave: 'status', rotulo: 'Status' },
      { chave: 'previsao_entrega', rotulo: 'Previsão', tipo: 'data' },
      { chave: 'condicao_pagamento', rotulo: 'Condição' },
      { chave: 'valor', rotulo: 'Valor', tipo: 'moeda', totalizar: true },
    ],
    agrupavel: ['negocio', 'fornecedor', 'status'],
    ordem: { chave: 'data_pedido', desc: true },
  },
  {
    id: 'compras-recebimentos',
    titulo: 'Recebimentos de compra',
    area: 'Operação',
    descricao: 'Recebimentos com nota, com marca de "divergente" quando o valor da nota não bate com o valor dos itens.',
    view: 'vw_rel_compras_recebimentos',
    filtros: ['negocio', 'periodo'],
    campoData: 'data',
    colunas: [
      { chave: 'data', rotulo: 'Data', tipo: 'data' },
      { chave: 'pedido', rotulo: 'Pedido', tipo: 'numero' },
      { chave: 'negocio', rotulo: 'Negócio' },
      { chave: 'fornecedor', rotulo: 'Fornecedor' },
      { chave: 'nota_numero', rotulo: 'Nota' },
      { chave: 'nota_valor', rotulo: 'Nota (R$)', tipo: 'moeda', totalizar: true },
      { chave: 'valor_recebido', rotulo: 'Recebido (R$)', tipo: 'moeda', totalizar: true },
      { chave: 'situacao', rotulo: 'Situação' },
    ],
    agrupavel: ['fornecedor', 'situacao', 'negocio'],
    ordem: { chave: 'data', desc: true },
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
      { chave: 'negocio', rotulo: 'Negócio' },
    ],
    agrupavel: ['pessoa', 'negocio'],
    ordem: { chave: 'dias_atraso', desc: true },
  },
  {
    id: 'api-consultas',
    titulo: 'Consultas à API',
    area: 'Comercial',
    descricao: 'Quem consultou (token) o quê, quando e se achou o cliente — auditoria das integrações externas (ex.: Leveduca).',
    view: 'vw_rel_api_consultas',
    filtros: ['negocio'],
    colunas: [
      { chave: 'criado_em', rotulo: 'Quando', tipo: 'data' },
      { chave: 'token', rotulo: 'Token' },
      { chave: 'negocio', rotulo: 'Negócio' },
      { chave: 'documento_mascarado', rotulo: 'CPF/CNPJ' },
      { chave: 'situacao', rotulo: 'Situação' },
    ],
    agrupavel: ['token', 'negocio', 'situacao'],
    ordem: { chave: 'criado_em', desc: true },
  },
  {
    id: 'bloqueios',
    titulo: 'Bloqueios e desbloqueios',
    area: 'Financeiro',
    descricao: 'Histórico do bloqueio assistido/automático: quem foi bloqueado ou desbloqueado, quando e se foi o robô ou um clique manual.',
    view: 'vw_rel_bloqueios',
    filtros: ['negocio', 'pessoa'],
    colunas: [
      { chave: 'criado_em', rotulo: 'Sugerido em', tipo: 'data' },
      { chave: 'executado_em', rotulo: 'Executado em', tipo: 'data' },
      { chave: 'cliente', rotulo: 'Cliente' },
      { chave: 'negocio', rotulo: 'Negócio' },
      { chave: 'tipo', rotulo: 'Ação' },
      { chave: 'status', rotulo: 'Status' },
      { chave: 'automatico', rotulo: 'Automático' },
      { chave: 'motivo', rotulo: 'Motivo' },
    ],
    agrupavel: ['negocio', 'tipo', 'status', 'automatico'],
    ordem: { chave: 'criado_em', desc: true },
  },
  {
    id: 'pontos-pontualidade',
    titulo: 'Pontos de pontualidade',
    area: 'Financeiro',
    descricao: 'Extrato de pontos ganhos por pagar antes do vencimento — fatura a fatura, por cliente. Ciclo 01/10 a 30/09.',
    view: 'vw_rel_pontos_pontualidade',
    filtros: ['negocio', 'pessoa'],
    colunas: [
      { chave: 'criado_em', rotulo: 'Concedido em', tipo: 'data' },
      { chave: 'cliente', rotulo: 'Cliente' },
      { chave: 'negocio', rotulo: 'Negócio' },
      { chave: 'fatura', rotulo: 'Fatura' },
      { chave: 'vencimento', rotulo: 'Vencimento', tipo: 'data' },
      { chave: 'pago_em', rotulo: 'Pago em', tipo: 'data' },
      { chave: 'pontos', rotulo: 'Pontos', tipo: 'numero', totalizar: true },
      { chave: 'ciclo_inicio', rotulo: 'Ciclo', tipo: 'data' },
    ],
    agrupavel: ['cliente', 'negocio', 'ciclo_inicio'],
    ordem: { chave: 'criado_em', desc: true },
  },
]

export const AREAS: Area[] = ['Financeiro', 'Clientes e contratos', 'Operação', 'Comercial']
export const relatorioPorId = (id: string) => RELATORIOS.find((r) => r.id === id)
