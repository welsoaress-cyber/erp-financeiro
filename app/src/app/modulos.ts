import type { DefinicaoModulo, MenuGrupo } from '../core/modulos/tipos'
import { moduloDashboard } from '../modules/dashboard'
import { moduloNovidades } from '../modules/novidades'
import { moduloFinanceiro } from '../modules/financeiro'
import { moduloContas } from '../modules/contas'
import { moduloCartoes } from '../modules/cartoes'
import { moduloCategorias } from '../modules/categorias'
import { moduloNegocios } from '../modules/negocios'
import { moduloCentrosCusto } from '../modules/centros_custo'
import { moduloPessoas, moduloFornecedores } from '../modules/pessoas'
import { moduloLeads } from '../modules/leads'
import { moduloContratos } from '../modules/contratos'
import { moduloRh, moduloRhPonto, moduloRhFerias } from '../modules/rh'
import { moduloApps } from '../modules/apps'
import { moduloNotificacoes } from '../modules/notificacoes'
import { moduloDisparos } from '../modules/disparos'
import { moduloFtth } from '../modules/ftth'
import { moduloEstoque } from '../modules/estoque'
import { moduloComprasRequisicoes, moduloComprasPedidos, moduloComprasRecebimento } from '../modules/compras'
import { moduloOs } from '../modules/os'
import { moduloGerencial } from '../modules/gerencial'
import { moduloRelatorios } from '../modules/relatorios'
import { moduloPortal } from '../modules/portal'
import { moduloIndicacoes } from '../modules/indicacoes'
import { moduloConfiguracoes } from '../modules/configuracoes'

/** Registro único de módulos. A ordem no menu é definida por GRUPOS + RAIZ. */
export const MODULOS: DefinicaoModulo[] = [
  moduloDashboard,
  moduloNovidades,
  moduloFinanceiro,
  moduloContas,
  moduloCartoes,
  moduloCategorias,
  moduloNegocios,
  moduloCentrosCusto,
  moduloPessoas,
  moduloFornecedores,
  moduloLeads,
  moduloContratos,
  moduloRh,
  moduloRhPonto,
  moduloRhFerias,
  moduloIndicacoes,
  moduloFtth,
  moduloEstoque,
  moduloComprasRequisicoes,
  moduloComprasPedidos,
  moduloComprasRecebimento,
  moduloOs,
  moduloGerencial,
  moduloRelatorios,
  moduloApps,
  moduloNotificacoes,
  moduloDisparos,
  moduloPortal,
  moduloConfiguracoes,
]

/** Módulos raiz (fora de grupos), na ordem do menu. */
export const RAIZ: string[] = ['dashboard', 'novidades', 'financeiro', 'portal', 'configuracoes']

/** Grupos que agrupam módulos no menu lateral (colapsáveis). */
export const GRUPOS: MenuGrupo[] = [
  { id: 'cadastros', titulo: 'Cadastros', icone: 'pessoas',
    modulos: ['pessoas', 'leads', 'negocios', 'contratos', 'categorias', 'centros_custo', 'contas', 'cartoes'] },
  { id: 'suprimentos', titulo: 'Suprimentos', icone: 'estoque',
    modulos: ['estoque', 'compras_requisicoes', 'compras_pedidos', 'compras_recebimento', 'fornecedores'] },
  { id: 'operacao', titulo: 'Operação', icone: 'os',
    modulos: ['os', 'ftth', 'indicacoes'] },
  { id: 'rh', titulo: 'RH', icone: 'rh',
    modulos: ['rh', 'rh_ponto', 'rh_ferias'] },
  { id: 'comunicacao', titulo: 'Comunicação', icone: 'notificacoes',
    modulos: ['notificacoes', 'disparos', 'apps'] },
  { id: 'analise', titulo: 'Análise', icone: 'gerencial',
    modulos: ['gerencial', 'relatorios'] },
]
