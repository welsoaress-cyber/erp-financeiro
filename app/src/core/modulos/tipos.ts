import type { ComponentType } from 'react'
import type { NomeIcone } from '../ui/Icone'

/**
 * Contrato de um módulo. Adicionar um módulo ao sistema = criar a pasta em
 * src/modules/<nome>, exportar esta definição e registrá-la em src/app/modulos.ts.
 * Menu e rotas são gerados a partir do registro.
 */
export interface DefinicaoModulo {
  id: string
  titulo: string
  rota: string
  icone: NomeIcone
  Pagina: ComponentType
  /** Telas secundárias do módulo (fora do menu), ex.: /configuracoes/importar */
  subRotas?: { rota: string; Pagina: ComponentType }[]
}
