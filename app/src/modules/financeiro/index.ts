import type { DefinicaoModulo } from '../../core/modulos/tipos'
import { LancamentosPage } from '../lancamentos/pages/LancamentosPage'
import { ContasPagarPage, ContasReceberPage } from './pages/ContasPage'

/** Módulo Financeiro: Lançamentos (movido), Contas a Receber e Contas a Pagar compartilham o mês selecionado. */
export const moduloFinanceiro: DefinicaoModulo = {
  id: 'financeiro',
  titulo: 'Financeiro',
  rota: '/financeiro',
  icone: 'financeiro',
  Pagina: LancamentosPage,
  submodulos: [
    { id: 'lancamentos', titulo: 'Lançamentos', rota: '/financeiro/lancamentos', Pagina: LancamentosPage },
    { id: 'receber', titulo: 'Contas a receber', rota: '/financeiro/receber', Pagina: ContasReceberPage },
    { id: 'pagar', titulo: 'Contas a pagar', rota: '/financeiro/pagar', Pagina: ContasPagarPage },
  ],
}
