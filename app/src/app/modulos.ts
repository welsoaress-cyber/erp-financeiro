import type { DefinicaoModulo } from '../core/modulos/tipos'
import { moduloDashboard } from '../modules/dashboard'
import { moduloLancamentos } from '../modules/lancamentos'
import { moduloContas } from '../modules/contas'
import { moduloCategorias } from '../modules/categorias'
import { moduloNegocios } from '../modules/negocios'
import { moduloPessoas } from '../modules/pessoas'
import { moduloContratos } from '../modules/contratos'
import { moduloConfiguracoes } from '../modules/configuracoes'

/** Registro único de módulos. A ordem aqui é a ordem do menu. */
export const MODULOS: DefinicaoModulo[] = [
  moduloDashboard,
  moduloLancamentos,
  moduloContas,
  moduloCategorias,
  moduloNegocios,
  moduloPessoas,
  moduloContratos,
  moduloConfiguracoes,
]
