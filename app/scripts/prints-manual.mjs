// Gera os prints do manual do administrador (docs/manual/img/*.png).
// Sobe o build (vite preview) e intercepta a API do Supabase com dados de
// demonstração — nenhum acesso à produção. Uso:
//   cd app && npm run build && node scripts/prints-manual.mjs
import { chromium } from 'playwright'
import { spawn } from 'node:child_process'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const raiz = dirname(dirname(fileURLToPath(import.meta.url)))
const DIR = join(dirname(raiz), 'docs', 'manual', 'img')
mkdirSync(DIR, { recursive: true })

// ---------------------------------------------------------------------------
// Dados de demonstração
// ---------------------------------------------------------------------------
const ORG = 'a0000000-0000-4000-8000-000000000001'
const NEG = 'b0000000-0000-4000-8000-000000000001'
const hoje = new Date()
const iso = (d) => d.toISOString().slice(0, 10)
const mesAtual = iso(hoje).slice(0, 7)
const dia = (n) => iso(new Date(hoje.getFullYear(), hoje.getMonth(), n))
const mesDelta = (k) => { const d = new Date(hoje.getFullYear(), hoje.getMonth() + k, 1); return d.toISOString().slice(0, 7) }
const id = (p, n) => `${p}0000000-0000-4000-8000-${String(n).padStart(12, '0')}`

const pessoas = [
  { id: id('c', 1), organizacao_id: ORG, tipo: 'fisica', nome: 'Maria Souza', documento: '52998224725', email: 'maria@email.com', telefone: '92988881111', endereco: 'Rua das Flores, 120 — Centro', ativo: true, receber_avisos: true, data_nascimento: '1990-05-10', login_servidor: null, observacao: null, criado_em: dia(1), atualizado_em: dia(1) },
  { id: id('c', 2), organizacao_id: ORG, tipo: 'fisica', nome: 'José Lima', documento: '11144477735', email: null, telefone: '92988882222', endereco: 'Av. Brasil, 45', ativo: true, receber_avisos: true, data_nascimento: null, login_servidor: null, observacao: null, criado_em: dia(1), atualizado_em: dia(1) },
  { id: id('c', 3), organizacao_id: ORG, tipo: 'fisica', nome: 'Ana Pereira', documento: null, email: null, telefone: '92988883333', endereco: 'Rua do Sol, 8', ativo: true, receber_avisos: false, data_nascimento: null, login_servidor: null, observacao: null, criado_em: dia(1), atualizado_em: dia(1) },
  { id: id('c', 9), organizacao_id: ORG, tipo: 'fisica', nome: 'João Batista (Técnico)', documento: null, email: null, telefone: '92988889999', endereco: null, ativo: true, receber_avisos: false, data_nascimento: null, login_servidor: null, observacao: 'Técnico (comissões)', criado_em: dia(1), atualizado_em: dia(1) },
]
const contas = [
  { id: id('d', 1), organizacao_id: ORG, nome: 'Caixa Servnet', tipo: 'dinheiro', saldo_inicial: 500, data_inicio: '2026-01-01', ativo: true, saldo: 3240.5, movimentos: 42, negocio_id: NEG },
  { id: id('d', 2), organizacao_id: ORG, nome: 'Sicoob Servnet', tipo: 'corrente', saldo_inicial: 2000, data_inicio: '2026-01-01', ativo: true, saldo: 12480.0, movimentos: 87, negocio_id: NEG },
  { id: id('d', 3), organizacao_id: ORG, nome: 'Cartão Nubank', tipo: 'credito', saldo_inicial: 0, data_inicio: '2026-01-01', ativo: true, saldo: -830.4, movimentos: 12, negocio_id: null },
]
const categorias = [
  { id: id('e', 1), organizacao_id: ORG, nome: 'Mensalidades', tipo: 'receita', categoria_pai_id: null, ativo: true },
  { id: id('e', 2), organizacao_id: ORG, nome: 'Energia', tipo: 'despesa', categoria_pai_id: null, ativo: true },
  { id: id('e', 3), organizacao_id: ORG, nome: 'Link dedicado', tipo: 'despesa', categoria_pai_id: null, ativo: true },
  { id: id('e', 4), organizacao_id: ORG, nome: 'Comissões', tipo: 'despesa', categoria_pai_id: null, ativo: true },
  { id: id('e', 5), organizacao_id: ORG, nome: 'Compra de Estoque', tipo: 'despesa', categoria_pai_id: null, ativo: true },
]
const negocios = [{ id: NEG, organizacao_id: ORG, nome: 'Servnet', slug: 'servnet', descricao: 'Provedor de internet', ativo: true, criado_em: '2026-01-01', atualizado_em: '2026-01-01' }]
const planos = [
  { id: id('f', 1), organizacao_id: ORG, negocio_id: NEG, nome: 'Fibra 300 Mega', descricao: null, valor_tabela: 99.9, periodicidade: 'mensal', ativo: true },
  { id: id('f', 2), organizacao_id: ORG, negocio_id: NEG, nome: 'Fibra 600 Mega', descricao: null, valor_tabela: 129.9, periodicidade: 'mensal', ativo: true },
]
const contratos = [
  { id: id('1', 1), organizacao_id: ORG, negocio_id: NEG, pessoa_id: id('c', 1), plano_id: id('f', 1), codigo: 1, valor: 99.9, periodicidade: 'mensal', data_inicio: '2026-02-10', data_fim: null, dia_vencimento: 10, status: 'ativo', observacao: null, faturamento_automatico: true, faturar_desde: '2026-02-01', conta_id: id('d', 2), tipo_financeiro: 'receita' },
  { id: id('1', 2), organizacao_id: ORG, negocio_id: NEG, pessoa_id: id('c', 2), plano_id: id('f', 2), codigo: 2, valor: 129.9, periodicidade: 'mensal', data_inicio: '2026-04-05', data_fim: null, dia_vencimento: 5, status: 'ativo', observacao: null, faturamento_automatico: true, faturar_desde: '2026-04-01', conta_id: id('d', 2), tipo_financeiro: 'receita' },
  { id: id('1', 3), organizacao_id: ORG, negocio_id: NEG, pessoa_id: id('c', 3), plano_id: id('f', 1), codigo: 3, valor: 99.9, periodicidade: 'mensal', data_inicio: '2026-06-20', data_fim: null, dia_vencimento: 20, status: 'suspenso', observacao: 'Suspenso por inadimplência', faturamento_automatico: true, faturar_desde: '2026-07-01', conta_id: id('d', 2), tipo_financeiro: 'receita' },
]
const lanc = (n, extra) => ({
  id: id('2', n), organizacao_id: ORG, tipo: 'receita', descricao: 'Mensalidade', valor: 99.9,
  data_competencia: dia(10), data_vencimento: dia(10), data_efetivacao: null, status: 'previsto',
  conta_id: id('d', 2), conta_destino_id: null, categoria_id: id('e', 1), observacao: null, origem: 'faturamento',
  negocio_id: NEG, pessoa_id: id('c', 1), contrato_id: id('1', 1), recorrente: false, tipo_recorrencia: null,
  periodicidade: null, numero_parcelas: null, parcela_atual: null, data_fim_recorrencia: null,
  lancamento_origem_id: null, cancelado_em: null, motivo_cancelamento: null, criado_em: dia(1) + 'T09:00:00Z', atualizado_em: dia(1) + 'T09:00:00Z', ...extra,
})
const lancamentos = [
  lanc(1, { descricao: 'Mensalidade Fibra 300 — Maria Souza', status: 'efetivado', data_efetivacao: dia(9) }),
  lanc(2, { descricao: 'Mensalidade Fibra 600 — José Lima', valor: 129.9, pessoa_id: id('c', 2), contrato_id: id('1', 2), data_vencimento: dia(5), data_competencia: dia(5) }),
  lanc(3, { descricao: 'Mensalidade Fibra 300 — Ana Pereira', pessoa_id: id('c', 3), contrato_id: id('1', 3), data_vencimento: dia(2), data_competencia: dia(2) }),
  lanc(4, { tipo: 'despesa', descricao: 'Energia da central', valor: 480, categoria_id: id('e', 2), pessoa_id: null, contrato_id: null, status: 'efetivado', data_efetivacao: dia(6), conta_id: id('d', 1) }),
  lanc(5, { tipo: 'despesa', descricao: 'Link dedicado 1 Gbps', valor: 1500, categoria_id: id('e', 3), pessoa_id: null, contrato_id: null, data_vencimento: dia(15), data_competencia: dia(15) }),
  lanc(6, { tipo: 'despesa', descricao: 'Comissão OS00111092026A — João Batista', valor: 49.95, categoria_id: id('e', 4), pessoa_id: id('c', 9), contrato_id: null, data_vencimento: dia(25), data_competencia: dia(25) }),
]
const tecnicos = [{ id: id('3', 1), organizacao_id: ORG, negocio_id: NEG, pessoa_id: id('c', 9), usuario_id: 'u2000000-0000-4000-8000-000000000002', login: 'joao', nome: 'João Batista', telefone: '92988889999', ativo: true, criado_em: dia(1), atualizado_em: dia(1) }]
const os = (n, extra) => ({
  id: id('4', n), organizacao_id: ORG, negocio_id: NEG, numero: `OS00${n}${iso(hoje).split('-').reverse().join('')}A`, os_origem_id: null, retorno: false,
  contrato_id: id('1', 1), pessoa_id: id('c', 1), tecnico_id: id('3', 1), cto_id: null, tipo: 'reparo', prioridade: 'normal', status: 'aberto', aberto_via: 'admin',
  descricao: 'Cliente sem internet, luz vermelha no modem', data_agendada: iso(hoje), hora_agendada: '14:00:00', remarcacao_data: null, remarcacao_hora: null, remarcacao_motivo: null,
  data_ciencia: null, data_inicio: null, data_fim: null, pausado_em: null, tempo_total_minutos: null, tempo_pausa_minutos: 0, tempo_execucao_minutos: null,
  diagnostico: null, sinal_dbm: null, avaliacao_resolvido: null, avaliacao_nota: null, comissao_lancamento_id: null, observacao: null, criado_em: dia(Math.max(1, hoje.getDate() - 1)) + 'T08:00:00Z', atualizado_em: dia(1) + 'T08:00:00Z', ...extra,
})
const ordens = [
  os(1, { tipo: 'instalacao', descricao: 'Instalar Fibra 600 — casa nova', pessoa_id: id('c', 2), contrato_id: id('1', 2), prioridade: 'normal' }),
  os(2, { status: 'em_atendimento', data_ciencia: dia(1) + 'T09:00:00Z', data_inicio: new Date().toISOString(), hora_agendada: '09:00:00' }),
  os(3, { status: 'encerrado', tipo: 'reparo', pessoa_id: id('c', 3), contrato_id: id('1', 3), data_fim: dia(Math.max(1, hoje.getDate() - 2)) + 'T16:30:00Z', tempo_total_minutos: 95, tempo_execucao_minutos: 40, diagnostico: 'conector', sinal_dbm: -19.5, avaliacao_resolvido: true, avaliacao_nota: 5 }),
  os(4, { tipo: 'rompimento', descricao: 'Rompimento na rota da Av. Brasil', pessoa_id: null, contrato_id: null, numero: 'MAN' + iso(hoje).split('-').reverse().join('') + 'A', cto_id: id('7', 3), prioridade: 'urgente', data_agendada: null, hora_agendada: null }),
]
const estoqueItens = [
  { id: id('5', 1), organizacao_id: ORG, negocio_id: NEG, categoria_id: id('6', 1), codigo: 'CABO-01', nome: 'Cabo drop 1FO', descricao: null, unidade_medida: 'metro', marca: null, modelo: null, valor_custo: 1.02, valor_venda: null, quantidade_atual: 820, quantidade_minima: 200, quantidade_maxima: null, localizacao: 'Bobina 2', ativo: true },
  { id: id('5', 2), organizacao_id: ORG, negocio_id: NEG, categoria_id: id('6', 2), codigo: 'ONU-ZTE', nome: 'ONU ZTE F601', descricao: null, unidade_medida: 'unidade', marca: 'ZTE', modelo: 'F601', valor_custo: 148.5, valor_venda: null, quantidade_atual: 14, quantidade_minima: 5, quantidade_maxima: null, localizacao: 'Prateleira A', ativo: true },
  { id: id('5', 3), organizacao_id: ORG, negocio_id: NEG, categoria_id: id('6', 3), codigo: 'CON-APC', nome: 'Conector rápido APC', descricao: null, unidade_medida: 'unidade', marca: null, modelo: null, valor_custo: 3.8, valor_venda: null, quantidade_atual: 36, quantidade_minima: 50, quantidade_maxima: null, localizacao: null, ativo: true },
]
const estoqueCategorias = [
  { id: id('6', 1), organizacao_id: ORG, negocio_id: NEG, nome: 'Cabos', descricao: null, ativo: true },
  { id: id('6', 2), organizacao_id: ORG, negocio_id: NEG, nome: 'Equipamentos', descricao: null, ativo: true },
  { id: id('6', 3), organizacao_id: ORG, negocio_id: NEG, nome: 'Conectores', descricao: null, ativo: true },
]
const estoqueMovs = [
  { id: id('m', 1), organizacao_id: ORG, negocio_id: NEG, item_id: id('5', 1), tipo: 'entrada', origem: 'compra', quantidade: 1000, valor_unitario: 1.02, valor_total: 1020, data: dia(2), pessoa_id: null, contrato_id: null, lancamento_id: null, instalacao_id: null, observacao: 'Compra bobina', usuario_id: null, criado_em: dia(2) + 'T10:00:00Z' },
  { id: id('m', 2), organizacao_id: ORG, negocio_id: NEG, item_id: id('5', 1), tipo: 'saida', origem: 'transferencia', quantidade: 180, valor_unitario: 1.02, valor_total: 183.6, data: dia(3), pessoa_id: null, contrato_id: null, lancamento_id: null, instalacao_id: null, observacao: 'Bolsa: João Batista', usuario_id: null, criado_em: dia(3) + 'T08:30:00Z' },
  { id: id('m', 3), organizacao_id: ORG, negocio_id: NEG, item_id: id('5', 2), tipo: 'saida', origem: 'instalacao', quantidade: 1, valor_unitario: 148.5, valor_total: 148.5, data: dia(4), pessoa_id: id('c', 1), contrato_id: id('1', 1), lancamento_id: null, instalacao_id: null, observacao: 'Instalação Maria', usuario_id: null, criado_em: dia(4) + 'T15:00:00Z' },
]
const comodatos = [
  { id: id('8', 1), organizacao_id: ORG, negocio_id: NEG, item_id: id('5', 2), numero_serie: 'ZTEG12AB34CD', pessoa_id: id('c', 1), contrato_id: id('1', 1), tecnico_id: id('3', 1), status: 'instalado', data_instalacao: '2026-02-10', data_recolhimento: null, os_instalacao_id: id('4', 3), os_recolhimento_id: null, observacao: null, criado_em: dia(1), atualizado_em: dia(1) },
  { id: id('8', 2), organizacao_id: ORG, negocio_id: NEG, item_id: id('5', 2), numero_serie: 'ZTEG99XY88ZW', pessoa_id: id('c', 2), contrato_id: id('1', 2), tecnico_id: id('3', 1), status: 'instalado', data_instalacao: '2026-04-05', data_recolhimento: null, os_instalacao_id: null, os_recolhimento_id: null, observacao: null, criado_em: dia(1), atualizado_em: dia(1) },
  { id: id('8', 3), organizacao_id: ORG, negocio_id: NEG, item_id: id('5', 2), numero_serie: 'HWTC55AA66BB', pessoa_id: id('c', 3), contrato_id: id('1', 3), tecnico_id: null, status: 'trocado', data_instalacao: '2026-05-01', data_recolhimento: dia(2), os_instalacao_id: null, os_recolhimento_id: null, observacao: 'ONU queimada por raio', criado_em: dia(1), atualizado_em: dia(1) },
]
const ctoBase = (n, extra) => ({
  id: id('7', n), organizacao_id: ORG, negocio_id: NEG, codigo: `CTO-00${n}`, endereco: null, referencia: null,
  latitude: -3.09 - n * 0.004, longitude: -60.02 - n * 0.004, quantidade_portas: 8, splitter: '1x8', status: 'ativa', observacao: null,
  tipo: 'cto', pop_id: id('7', 1), rota_pop: null, lacre: null, olt_marca: null, olt_modelo: null, olt_ip: null, olt_portas_pon: null,
  ocupadas: 3, reservadas: 1, livres: 4, com_defeito: 0, drops_disponiveis: 1, criado_em: dia(1), atualizado_em: dia(1), ...extra,
})
const ctos = [
  ctoBase(1, { codigo: 'POP-01', tipo: 'pop', pop_id: null, splitter: null, quantidade_portas: 1, ocupadas: 0, reservadas: 0, livres: 1, drops_disponiveis: 0, latitude: -3.085, longitude: -60.012, olt_marca: 'Huawei', olt_modelo: 'MA5608T', olt_ip: '10.0.0.2', olt_portas_pon: 16 }),
  ctoBase(2, { codigo: 'CEO-01', tipo: 'ceo', splitter: '1x4', quantidade_portas: 1, ocupadas: 0, reservadas: 0, livres: 1, drops_disponiveis: 0, latitude: -3.095, longitude: -60.02 }),
  ctoBase(3, { codigo: 'CTO-001', pop_id: id('7', 2), latitude: -3.101, longitude: -60.028 }),
  ctoBase(4, { codigo: 'CTO-002', pop_id: id('7', 2), ocupadas: 7, reservadas: 1, livres: 0, drops_disponiveis: 0, latitude: -3.097, longitude: -60.033 }),
]
const bi = Array.from({ length: 13 }, (_, i) => {
  const k = i - 12
  const ativos = 120 + i * 4
  return {
    organizacao_id: ORG, negocio_id: NEG, negocio: 'Servnet', mes: mesDelta(k),
    novos: 4 + (i % 4), cancelamentos: i % 3, ativos_inicio: ativos - 3, ativos_fim: ativos,
    churn_pct: [0, 0.9, 1.7][i % 3], mrr: ativos * 104.3, ticket_medio: 104.3,
    previsto: ativos * 104.3, recebido: Math.round(ativos * 104.3 * 0.93), vencido_aberto: Math.round(ativos * 104.3 * 0.05),
    inadimplencia_pct: 5.0,
  }
})

const tabelas = {
  organizacao_membros: [{ organizacao_id: ORG, usuario_id: 'u1', papel: 'proprietario', criado_em: '2026-01-01', organizacoes: { id: ORG, nome: 'Grupo Tom' } }],
  contas, vw_saldo_contas: contas, categorias, negocios, pessoas, planos, contratos, lancamentos, tecnicos,
  ordens_servico: ordens, os_materiais: [], os_historico: [], os_fotos: [], reposicao_solicitacoes: [],
  tecnico_estoque: [
    { id: id('9', 1), organizacao_id: ORG, tecnico_id: id('3', 1), item_id: id('5', 1), quantidade: 145, quantidade_minima: 100 },
    { id: id('9', 2), organizacao_id: ORG, tecnico_id: id('3', 1), item_id: id('5', 2), quantidade: 2, quantidade_minima: 2 },
    { id: id('9', 3), organizacao_id: ORG, tecnico_id: id('3', 1), item_id: id('5', 3), quantidade: 18, quantidade_minima: 20 },
  ],
  tecnico_movimentacoes: [],
  vw_bolsa_tecnicos: [{ organizacao_id: ORG, tecnico_id: id('3', 1), negocio_id: NEG, tecnico: 'João Batista', ativo: true, itens_negativos: 0, itens_abaixo_minimo: 1, valor_em_campo: 513.9 }],
  estoque_itens: estoqueItens, estoque_categorias: estoqueCategorias, estoque_movimentacoes: estoqueMovs,
  estoque_instalacoes: [{ id: id('a', 1), organizacao_id: ORG, negocio_id: NEG, pessoa_id: id('c', 1), contrato_id: id('1', 1), porta_id: null, os_id: null, data: '2026-02-10', custo_material: 230.5, mao_de_obra: 120, custo_total: 350.5, tecnico: 'João Batista', observacao: null, criado_em: '2026-02-10' }],
  vw_payback_contrato: [
    { contrato_id: id('1', 1), organizacao_id: ORG, negocio_id: NEG, pessoa_id: id('c', 1), status: 'ativo', valor: 99.9, periodicidade: 'mensal', data_inicio: '2026-02-10', custo_instalacao: 350.5, instalacoes: 1, primeira_instalacao: '2026-02-10', mensalidade: 99.9, payback_estimado_meses: 4, recebido: 699.3, data_payback_real: '2026-06-10', payback_real_meses: 4 },
    { contrato_id: id('1', 2), organizacao_id: ORG, negocio_id: NEG, pessoa_id: id('c', 2), status: 'ativo', valor: 129.9, periodicidade: 'mensal', data_inicio: '2026-04-05', custo_instalacao: 412.8, instalacoes: 1, primeira_instalacao: '2026-04-05', mensalidade: 129.9, payback_estimado_meses: 4, recebido: 519.6, data_payback_real: null, payback_real_meses: null },
  ],
  vw_os_custo_contrato: [{ organizacao_id: ORG, contrato_id: id('1', 3), chamados: 2, custo_material: 42.6 }],
  vw_estoque_consumo_mensal: [
    { organizacao_id: ORG, negocio_id: NEG, mes: mesAtual, tipo: 'saida', origem: 'instalacao', movimentacoes: 6, quantidade: 480, valor_total: 712.4 },
    { organizacao_id: ORG, negocio_id: NEG, mes: mesAtual, tipo: 'saida', origem: 'perda', movimentacoes: 1, quantidade: 5, valor_total: 5.1 },
  ],
  vw_estoque_consumo_item: [{ organizacao_id: ORG, negocio_id: NEG, item_id: id('5', 1), mes: mesAtual, quantidade: 460, valor_total: 469.2, movimentacoes: 5 }],
  comodatos, comodato_historico: [],
  pix_cobrancas: [
    { id: id('b', 1), organizacao_id: ORG, negocio_id: NEG, pessoa_id: id('c', 1), lancamento_id: id('2', 1), valor: 99.9, status: 'pago', criado_em: dia(8) + 'T10:00:00Z', pago_em: dia(9) + 'T11:20:00Z' },
    { id: id('b', 2), organizacao_id: ORG, negocio_id: NEG, pessoa_id: id('c', 2), lancamento_id: id('2', 2), valor: 129.9, status: 'pendente', criado_em: dia(Math.max(1, hoje.getDate() - 1)) + 'T09:00:00Z', pago_em: null },
  ],
  bloqueios: [
    { id: id('b', 5), organizacao_id: ORG, negocio_id: NEG, contrato_id: id('1', 3), pessoa_id: id('c', 3), tipo: 'bloqueio', status: 'pendente', motivo: '2 cobrança(s) vencida(s) desde ' + dia(2).split('-').reverse().join('/') + ' · R$ 199,80', criado_em: new Date().toISOString() },
  ],
  vw_bi_mensal_negocio: bi,
  vw_resultado_mensal_negocio: [{ organizacao_id: ORG, mes: mesAtual, negocio_id: NEG, receitas: 12480.9, despesas: 6320.4, resultado: 6160.5 }],
  notificacoes_config: [{ id: id('n', 1), organizacao_id: ORG, negocio_id: NEG, numero_whatsapp: '+5592999998888', provedor: 'evolution', instancia: 'servnet', ativo: true, dias_antes: 3, dias_apos: 3, hora_inicio: '08:00', hora_fim: '18:00' }],
  notificacoes_log: [
    { id: id('n', 5), organizacao_id: ORG, negocio_id: NEG, contrato_id: id('1', 1), pessoa_id: id('c', 1), lancamento_id: id('2', 1), os_id: null, tipo: 'proximo_vencimento', data_referencia: dia(10), numero_destino: '+5592988881111', mensagem: 'Olá Maria! Sua fatura...', status: 'enviado', provedor: 'evolution', erro: null, data_envio: dia(7) + 'T09:05:00Z', criado_em: dia(7) + 'T09:00:00Z' },
  ],
  vw_ctos_ocupacao: ctos, ctos, cto_portas: [], cto_historico: [],
  olt_status: [{ pop_id: id('7', 1), organizacao_id: ORG, online: true, latencia_ms: 4, ultima_verificacao: new Date().toISOString(), mudou_em: dia(1) }],
  aceites_contrato: [{ id: id('t', 1), organizacao_id: ORG, contrato_id: id('1', 1), pessoa_id: id('c', 1), data_aceite: '2026-02-10T14:22:00Z', ip: '187.10.20.30' }],
  portal_config: [{ id: id('p', 1), organizacao_id: ORG, negocio_id: NEG, ativo: true, logo_url: null, cor_primaria: '#1e3a8a', texto_promocional: 'Indique um amigo e ganhe 1 mês grátis!', chave_pix: 'pix@servnet.net.br', instrucoes_pagamento: null, beneficio_indicacao: 0, tema: 'escuro', whatsapp_suporte: '5592999998888', beneficio_tipo: 'mes_gratis', fidelidade_ativa: true, site_url: null, pix_automatico: true, conta_pix_id: id('d', 2), contrato_modelo: 'TERMO…' }],
  vw_resultado_por_contrato: contratos.map((c) => ({ contrato_id: c.id, organizacao_id: ORG, receitas: 599.4, despesas: 350.5, resultado: 248.9, lancamentos: 6, primeiro_lancamento: c.data_inicio, ultimo_lancamento: dia(9) })),
  vw_receita_recorrente: [{ negocio_id: NEG, organizacao_id: ORG, negocio: 'Servnet', contratos_ativos: 2, contratos_suspensos: 1, mrr: 229.8 }],
}

const rpcs = {
  saldo_inicial_mes: [{ negocio_id: NEG, saldo: 9800 }, { negocio_id: null, saldo: 1520.4 }],
  projecao_contratos: [],
  gerar_bloqueios: { bloqueios: 1, desbloqueios: 0 },
  ftth_abaixo_de: [
    { id: id('7', 3), codigo: 'CTO-001', tipo: 'cto', nivel: 2, clientes: 3 },
    { id: id('7', 4), codigo: 'CTO-002', tipo: 'cto', nivel: 2, clientes: 7 },
  ],
  os_info_cliente: [{ cliente: 'Maria Souza', telefone: '92988881111', endereco: 'Rua das Flores, 120 — Centro', contrato: '#001', cto: 'CTO-001' }],
  portal_resumo: {
    pessoa: { id: id('c', 1), nome: 'Maria Souza', documento: '52998224725', email: 'maria@email.com', telefone: '92988881111', receber_avisos: true, tem_nascimento: true },
    codigo_indicacao: 'MARIA123', em_aberto: 1, vencidas: 0, proximo_vencimento: dia(10), contratos_ativos: 1, indicacoes_convertidas: 2,
    negocios: [{ id: NEG, nome: 'Servnet', portal: { ativo: true, logo_url: null, cor_primaria: '#1e3a8a', texto_promocional: 'Indique um amigo e ganhe 1 mês grátis!', chave_pix: 'pix@servnet.net.br', instrucoes_pagamento: null, beneficio_indicacao: 0, tema: 'escuro', whatsapp_suporte: '5592999998888', beneficio_tipo: 'mes_gratis', fidelidade_ativa: true, site_url: null } }],
  },
  portal_faturas: [
    { id: id('2', 1), negocio: 'Servnet', contrato_codigo: 1, plano: 'Fibra 300 Mega', descricao: 'Mensalidade ' + mesAtual, valor: 99.9, data_vencimento: dia(10), data_efetivacao: null, status: 'previsto', situacao: 'pendente', observacao: null, chave_pix: 'pix@servnet.net.br', instrucoes_pagamento: null },
    { id: id('2', 9), negocio: 'Servnet', contrato_codigo: 1, plano: 'Fibra 300 Mega', descricao: 'Mensalidade ' + mesDelta(-1), valor: 99.9, data_vencimento: mesDelta(-1) + '-10', data_efetivacao: mesDelta(-1) + '-09', status: 'efetivado', situacao: 'paga', observacao: null, chave_pix: null, instrucoes_pagamento: null },
  ],
  portal_proximas_faturas: [{ contrato_codigo: 1, negocio: 'Servnet', plano: 'Fibra 300 Mega', competencia: mesDelta(1) + '-01', data_vencimento: mesDelta(1) + '-10', valor: 99.9 }],
  portal_pagamentos: [{ id: id('2', 9), data_pagamento: mesDelta(-1) + '-09', valor: 99.9, descricao: 'Mensalidade ' + mesDelta(-1), negocio: 'Servnet', contrato_codigo: 1, forma: 'Pix' }],
  portal_contratos: [{ id: id('1', 1), codigo: 1, negocio: 'Servnet', plano: 'Fibra 300 Mega', plano_descricao: '300 Mega de fibra óptica', valor: 99.9, periodicidade: 'mensal', data_inicio: '2026-02-10', data_fim: null, dia_vencimento: 10, status: 'ativo', proxima_renovacao: null, descontos_pendentes: 0 }],
  portal_promocoes: [], portal_indicacoes: [], portal_status_rede: [], portal_solicitacoes_cliente: [],
  portal_minhas_visitas: [
    { id: id('4', 2), numero: ordens[1].numero, tipo: 'reparo', status: 'em_atendimento', descricao: 'Sem internet: luz vermelha no modem', data_agendada: iso(hoje), hora_agendada: '09:00:00', remarcacao_data: null, remarcacao_hora: null, remarcacao_motivo: null, tecnico: 'João Batista', avaliacao_resolvido: null, avaliacao_nota: null, aberto_via: 'portal', criado_em: dia(1) + 'T08:00:00Z' },
  ],
  portal_meus_aceites: [{ contrato_id: id('1', 1), codigo: 1, negocio: 'Servnet', plano: 'Fibra 300 Mega', aceito: true, data_aceite: '2026-02-10T14:22:00Z' }],
  portal_pix_cobranca: [],
}

// ---------------------------------------------------------------------------
// Interceptação
// ---------------------------------------------------------------------------
const PNG_CINZA = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGPYtnUrAAVzAr7Ky7X8AAAAAElFTkSuQmCC', 'base64')

function filtrar(rows, url) {
  let out = rows
  for (const [k, v] of url.searchParams.entries()) {
    if (['select', 'order', 'limit', 'offset', 'on_conflict'].includes(k)) continue
    if (typeof v === 'string' && v.startsWith('eq.')) {
      const alvo = v.slice(3)
      out = out.filter((r) => !(k in r) || String(r[k]) === alvo)
    }
    if (typeof v === 'string' && v.startsWith('not.')) continue
  }
  return out
}

function sessao(usuario) {
  const agora = Math.floor(Date.now() / 1000)
  return {
    access_token: 'demo-token-' + usuario.id, token_type: 'bearer', expires_in: 3600 * 24, expires_at: agora + 3600 * 24,
    refresh_token: 'demo-refresh', user: usuario,
  }
}
const usuarios = {
  admin: { id: 'u1', aud: 'authenticated', role: 'authenticated', email: 'ana@grupotom.com.br', email_confirmed_at: '2026-01-01T00:00:00Z', app_metadata: {}, user_metadata: { nome: 'Ana' }, created_at: '2026-01-01T00:00:00Z' },
  tecnico: { id: 'u2000000-0000-4000-8000-000000000002', aud: 'authenticated', role: 'authenticated', email: 'joao@tecnico.local', email_confirmed_at: '2026-01-01T00:00:00Z', app_metadata: {}, user_metadata: { nome: 'João Batista', tecnico: 'true' }, created_at: '2026-01-01T00:00:00Z' },
  portal: { id: 'u3000000-0000-4000-8000-000000000003', aud: 'authenticated', role: 'authenticated', email: 'maria@email.com', email_confirmed_at: '2026-01-01T00:00:00Z', app_metadata: {}, user_metadata: { portal: 'true' }, created_at: '2026-01-01T00:00:00Z' },
}

async function instalarMock(context, papel) {
  await context.route('**/*.tile.openstreetmap.org/**', (r) => r.fulfill({ status: 200, contentType: 'image/png', body: PNG_CINZA }))
  await context.route('http://localhost:54321/**', async (route) => {
    const req = route.request()
    const url = new URL(req.url())
    const responder = (body, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) })
    if (url.pathname.startsWith('/auth/v1/token')) return responder(sessao(usuarios[papel]))
    if (url.pathname.startsWith('/auth/v1/user')) return responder(usuarios[papel])
    if (url.pathname.startsWith('/auth/v1/logout')) return responder({})
    if (url.pathname.startsWith('/rest/v1/rpc/')) {
      const fn = url.pathname.split('/').pop()
      const r = rpcs[fn]
      return responder(r === undefined ? [] : r)
    }
    if (url.pathname.startsWith('/rest/v1/')) {
      const tabela = url.pathname.split('/').pop()
      if (req.method() !== 'GET') return responder([], 201)
      let rows = filtrar(tabelas[tabela] ?? [], url)
      const accept = req.headers()['accept'] ?? ''
      if (accept.includes('vnd.pgrst.object')) return rows.length ? responder(rows[0]) : responder(null, 200)
      return responder(rows)
    }
    return responder([])
  })
}

// ---------------------------------------------------------------------------
// Captura
// ---------------------------------------------------------------------------
const BASE = 'http://localhost:4173'
const preview = spawn('npx', ['vite', 'preview', '--port', '4173', '--strictPort'], { cwd: raiz, stdio: 'ignore' })
await new Promise((r) => setTimeout(r, 2500))

const navegador = await chromium.launch({ executablePath: process.env.CHROME_BIN })
const espera = (ms) => new Promise((r) => setTimeout(r, ms))

async function capturar(page, nome, ms = 1200) {
  await espera(ms)
  await page.screenshot({ path: join(DIR, nome + '.png'), fullPage: true })
  console.log('✓', nome)
}

// ADMIN (desktop)
{
  const ctx = await navegador.newContext({ viewport: { width: 1380, height: 900 }, deviceScaleFactor: 1.5 })
  await instalarMock(ctx, 'admin')
  const page = await ctx.newPage()
  await page.goto(BASE + '/entrar')
  await capturar(page, '01-login', 800)
  await page.fill('input[type="email"], input[autocomplete="username"], input[placeholder*="mail" i], input:not([type="password"])', 'ana@grupotom.com.br').catch(() => undefined)
  await page.fill('input[type="password"]', 'senha-demo').catch(() => undefined)
  await page.click('button[type="submit"]').catch(() => undefined)
  await espera(1500)
  const telas = [
    ['/', '02-dashboard', 1500],
    ['/financeiro/lancamentos', '03-financeiro-lancamentos'],
    ['/financeiro/receber', '04-contas-a-receber'],
    ['/financeiro/pagar', '05-contas-a-pagar'],
    ['/financeiro/cobranca', '06-cobranca-bloqueios'],
    ['/contas', '07-contas'],
    ['/cartoes', '08-cartoes'],
    ['/categorias', '09-categorias'],
    ['/negocios', '10-negocios'],
    ['/pessoas', '11-pessoas'],
    ['/contratos', '12-contratos'],
    ['/ftth', '13-ftth-mapa', 2500],
    ['/estoque', '14-estoque-dashboard'],
    ['/os', '16-os-dashboard'],
    ['/apps', '20-apps'],
    ['/notificacoes', '21-notificacoes'],
    ['/disparos', '22-disparos'],
    ['/gerencial', '23-gerencial', 1600],
    ['/portal', '24-portal-admin'],
    ['/configuracoes', '25-configuracoes'],
  ]
  for (const [rota, nome, ms] of telas) {
    await page.goto(BASE + rota)
    await capturar(page, nome, ms ?? 1200)
  }
  // abas específicas
  await page.goto(BASE + '/estoque'); await espera(900)
  await page.getByRole('tab', { name: 'Comodato' }).click().catch(() => undefined)
  await capturar(page, '15-estoque-comodato')
  await page.goto(BASE + '/os'); await espera(900)
  await page.getByRole('tab', { name: 'Chamados' }).click().catch(() => undefined)
  await capturar(page, '17-os-chamados')
  await page.getByRole('tab', { name: 'Agenda' }).click().catch(() => undefined)
  await capturar(page, '18-os-agenda')
  await page.getByRole('tab', { name: 'Técnicos' }).click().catch(() => undefined)
  await capturar(page, '19-os-tecnicos')
  await ctx.close()
}

// TÉCNICO (celular)
{
  const ctx = await navegador.newContext({ viewport: { width: 420, height: 860 }, deviceScaleFactor: 2 })
  await instalarMock(ctx, 'tecnico')
  const page = await ctx.newPage()
  await page.goto(BASE + '/tecnico/entrar')
  await capturar(page, '30-tecnico-login', 800)
  await page.fill('input[autocomplete="username"]', 'joao').catch(() => undefined)
  await page.fill('input[type="password"]', 'senha-demo').catch(() => undefined)
  await page.click('button[type="submit"]').catch(() => undefined)
  await espera(1500)
  await page.goto(BASE + '/tecnico')
  await capturar(page, '31-tecnico-chamados', 1500)
  await page.goto(BASE + '/tecnico/bolsa')
  await capturar(page, '32-tecnico-bolsa')
  await ctx.close()
}

// PORTAL DO CLIENTE (celular)
{
  const ctx = await navegador.newContext({ viewport: { width: 460, height: 940 }, deviceScaleFactor: 2 })
  await instalarMock(ctx, 'portal')
  const page = await ctx.newPage()
  await page.goto(BASE + '/portal/entrar')
  await capturar(page, '40-portal-login', 900)
  // injeta a sessão direto (o login do portal é por CPF via Edge)
  await page.goto(BASE + '/portal/entrar-email').catch(() => undefined)
  await page.fill('input[type="email"]', 'maria@email.com').catch(() => undefined)
  await page.fill('input[type="password"]', 'senha-demo').catch(() => undefined)
  await page.click('button[type="submit"]').catch(() => undefined)
  await espera(1600)
  for (const [rota, nome] of [['/portal', '41-portal-inicio'], ['/portal/faturas', '42-portal-faturas'], ['/portal/chamados', '43-portal-chamados'], ['/portal/plano', '44-portal-plano']]) {
    await page.goto(BASE + rota)
    await capturar(page, nome, 1500)
  }
  await ctx.close()
}

await navegador.close()
preview.kill()
console.log('Prints em', DIR)
