import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import { fimDoMes } from '../../core/formatos'
import { useNegocios } from '../negocios/api'
import type { Linha, Relatorio } from './catalogo'

/** Filtros da tela (chave → valor); vazio = não aplicar. */
export type Filtros = Record<string, string>

export const chaveFavoritos = (org: string) => ['relatorios', org, 'favoritos'] as const

/** Executa o relatório: aplica os filtros conhecidos na view e devolve as linhas já preparadas. */
export function useExecutarRelatorio(rel: Relatorio | undefined, filtros: Filtros, ativo: boolean) {
  const { organizacao } = useOrganizacao()
  const negocios = useNegocios()
  return useQuery({
    queryKey: ['relatorios', organizacao.id, rel?.id, filtros],
    enabled: Boolean(rel) && ativo && negocios.isSuccess,
    queryFn: async (): Promise<Linha[]> => {
      if (!rel) return []
      let q = supabase.from(rel.view).select('*').eq('organizacao_id', organizacao.id)
      for (const [k, v] of Object.entries(rel.fixo ?? {})) q = q.eq(k, v)
      const campo = rel.campoData
      if (campo && rel.filtros.includes('mes') && filtros.mes) {
        // filtros.mes = 'AAAA-MM-01' (convenção do projeto); views mensais guardam o 1º dia do mês
        if (campo === 'mes') q = q.eq('mes', filtros.mes)
        else q = q.gte(campo, filtros.mes).lte(campo, fimDoMes(filtros.mes))
      }
      if (campo && rel.filtros.includes('periodo')) {
        if (filtros.de) q = q.gte(campo, filtros.de)
        if (filtros.ate) q = q.lte(campo, filtros.ate)
      }
      if (filtros.negocio) q = filtros.negocio === 'pessoal' ? q.is('negocio_id', null) : q.eq('negocio_id', filtros.negocio)
      if (filtros.pessoa) q = q.eq('pessoa_id', filtros.pessoa)
      if (filtros.categoria) q = q.eq('categoria_id', filtros.categoria)
      if (filtros.conta) q = q.eq('conta_id', filtros.conta)
      if (filtros.status) q = q.eq('status', filtros.status)
      else if (rel.filtros.includes('status')) q = q.neq('status', 'cancelado')
      if (filtros.tipo) q = q.eq('tipo', filtros.tipo)
      const { data, error } = await q.limit(5000)
      if (error) throw error
      // nome do centro de custo resolvido aqui (views agregadas trazem só negocio_id; nulo = Pessoal)
      const nome = new Map((negocios.data ?? []).map((n) => [n.id, n.nome]))
      const linhas = ((data ?? []) as Linha[]).map((l) => ('negocio_id' in l && l.negocio == null ? { ...l, negocio: l.negocio_id ? nome.get(String(l.negocio_id)) ?? '—' : 'Pessoal' } : l))
      return rel.preparar ? rel.preparar(linhas) : linhas
    },
  })
}

export interface Favorito { id: string; relatorio: string; nome: string; filtros: Filtros; criado_em: string }

export function useFavoritos() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: chaveFavoritos(organizacao.id),
    queryFn: async (): Promise<Favorito[]> => {
      const { data, error } = await supabase.from('relatorios_favoritos').select('id, relatorio, nome, filtros, criado_em').eq('organizacao_id', organizacao.id).order('nome')
      if (error) throw error
      return (data ?? []) as Favorito[]
    },
  })
}

export function useSalvarFavorito() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (p: { relatorio: string; nome: string; filtros: Filtros }) => {
      const { error } = await supabase.from('relatorios_favoritos').insert({ organizacao_id: organizacao.id, ...p })
      if (error) throw error
    },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: chaveFavoritos(organizacao.id) }) },
  })
}

export function useRemoverFavorito() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('remover_relatorio_favorito', { p_id: id })
      if (error) throw error
    },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: chaveFavoritos(organizacao.id) }) },
  })
}
