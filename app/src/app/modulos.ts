import type { DefinicaoModulo, MenuGrupo } from '../core/modulos/tipos'
import { moduloDashboard } from '../modules/dashboard'
import { moduloNovidades } from '../modules/novidades'
import { moduloFinanceiro } from '../modules/financeiro'
import { moduloContas } from '../modules/contas'
import { moduloCartoes } from '../modules/cartoes'
import { moduloCategorias } from '../modules/categorias'
import { moduloNegocios } from '../modules/negocios'
import { moduloCentrosCusto } from '../modules/centros_custo'
import { moduloPessoas } from '../modules/pessoas'
import { moduloContratos } from '../modules/contratos'
import { moduloApps } from '../modules/apps'
import { moduloNotificacoes } from '../modules/notificacoes'
import { moduloDisparos } from '../modules/disparos'
import { moduloFtth } from '../modules/ftth'
import { moduloEstoque } from '../modules/estoque'
import { moduloCompras } from '../modules/compras'
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
  moduloContratos,
  moduloIndicacoes,
  moduloFtth,
  moduloEstoque,
  moduloCompras,
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
    modulos: ['pessoas', 'negocios', 'contratos', 'categorias', 'centros_custo', 'contas', 'cartoes'] },
  { id: 'operacao', titulo: 'Operação', icone: 'estoque',
    modulos: ['estoque', 'compras', 'os', 'ftth', 'indicacoes'] },
  { id: 'comunicacao', titulo: 'Comunicação', icone: 'notificacoes',
    modulos: ['notificacoes', 'disparos', 'apps'] },
  { id: 'analise', titulo: 'Análise', icone: 'gerencial',
    modulos: ['gerencial', 'relatorios'] },
]
