import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { createClient } from '@supabase/supabase-js'
import { supabase } from '../../core/supabase/client'
import { useOrganizacao } from '../../core/organizacao/useOrganizacao'
import type { BolsaResumo, OrdemServico, OsCustoContrato, OsHistorico, OsMaterial, Tecnico, TecnicoEstoque, TecnicoMov } from './tipos'

const chave = (org: string) => ['os', org] as const

function useInvalidarOs() {
  const { organizacao } = useOrganizacao()
  const qc = useQueryClient()
  return () => {
    void qc.invalidateQueries({ queryKey: chave(organizacao.id) })
    void qc.invalidateQueries({ queryKey: ['estoque', organizacao.id] })
    void qc.invalidateQueries({ queryKey: ['lancamentos', organizacao.id] })
    void qc.invalidateQueries({ queryKey: ['contratos', organizacao.id] })
    void qc.invalidateQueries({ queryKey: ['pessoas', organizacao.id] })
  }
}

// ---------------------------------------------------------------------------
// Técnicos e bolsa
// ---------------------------------------------------------------------------
export function useTecnicos() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'tecnicos'],
    queryFn: async (): Promise<Tecnico[]> => {
      const { data, error } = await supabase.from('tecnicos').select('*').eq('organizacao_id', organizacao.id).order('nome')
      if (error) throw error
      return (data ?? []) as Tecnico[]
    },
  })
}

/** Cria/edita técnico; no cadastro cria também a pessoa (fornecedor das comissões). */
export function useSalvarTecnico() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidarOs()
  return useMutation({
    mutationFn: async (d: { id?: string; negocio_id: string; nome: string; telefone: string | null; ativo?: boolean }) => {
      if (d.id) {
        const { data, error } = await supabase.from('tecnicos').update({ nome: d.nome, telefone: d.telefone, ativo: d.ativo ?? true }).eq('id', d.id).select().single()
        if (error) throw error
        return data as Tecnico
      }
      const { data: pessoa, error: ep } = await supabase.from('pessoas')
        .insert({ organizacao_id: organizacao.id, nome: d.nome, telefone: d.telefone, observacao: 'Técnico (comissões)' }).select().single()
      if (ep) throw ep
      const { data, error } = await supabase.from('tecnicos')
        .insert({ organizacao_id: organizacao.id, negocio_id: d.negocio_id, pessoa_id: (pessoa as { id: string }).id, nome: d.nome, telefone: d.telefone }).select().single()
      if (error) throw error
      return data as Tecnico
    },
    onSuccess: invalidar,
  })
}

export function useBolsa(tecnicoId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'bolsa', tecnicoId ?? 'x'],
    enabled: tecnicoId !== null,
    queryFn: async (): Promise<TecnicoEstoque[]> => {
      const { data, error } = await supabase.from('tecnico_estoque').select('*').eq('tecnico_id', tecnicoId!)
      if (error) throw error
      return (data ?? []).map((b) => ({ ...b, quantidade: Number(b.quantidade), quantidade_minima: Number(b.quantidade_minima) })) as TecnicoEstoque[]
    },
  })
}

export function useBolsaResumo() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'bolsa-resumo'],
    queryFn: async (): Promise<BolsaResumo[]> => {
      const { data, error } = await supabase.from('vw_bolsa_tecnicos').select('*').eq('organizacao_id', organizacao.id)
      if (error) throw error
      return (data ?? []).map((b) => ({ ...b, itens_negativos: Number(b.itens_negativos), itens_abaixo_minimo: Number(b.itens_abaixo_minimo), valor_em_campo: Number(b.valor_em_campo) })) as BolsaResumo[]
    },
  })
}

export function useTecnicoMovs(tecnicoId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'tecnico-movs', tecnicoId ?? 'x'],
    enabled: tecnicoId !== null,
    queryFn: async (): Promise<TecnicoMov[]> => {
      const { data, error } = await supabase.from('tecnico_movimentacoes').select('*').eq('tecnico_id', tecnicoId!).order('criado_em', { ascending: false }).limit(100)
      if (error) throw error
      return (data ?? []).map((m) => ({ ...m, quantidade: Number(m.quantidade), valor_total: Number(m.valor_total) })) as TecnicoMov[]
    },
  })
}

function useRpc<T extends Record<string, unknown>>(fn: string) {
  const invalidar = useInvalidarOs()
  return useMutation({
    mutationFn: async (params: T) => {
      const { data, error } = await supabase.rpc(fn, params)
      if (error) throw error
      return data as unknown
    },
    onSuccess: invalidar,
  })
}

export const useAbastecerTecnico = () => useRpc<{ p_tecnico_id: string; p_item_id: string; p_quantidade: number; p_observacao?: string | null }>('abastecer_tecnico')
export const useDevolverTecnico = () => useRpc<{ p_tecnico_id: string; p_item_id: string; p_quantidade: number; p_observacao?: string | null }>('devolver_tecnico')
export const usePerdaTecnico = () => useRpc<{ p_tecnico_id: string; p_item_id: string; p_quantidade: number; p_avaria: boolean; p_motivo: string; p_defeito_fabrica?: boolean }>('perda_tecnico')

/** Mínimo da bolsa é configurável direto (linha nasce zerada). */
export function useDefinirMinimoBolsa() {
  const { organizacao } = useOrganizacao()
  const invalidar = useInvalidarOs()
  return useMutation({
    mutationFn: async (d: { tecnico_id: string; item_id: string; quantidade_minima: number; id?: string }) => {
      const q = d.id
        ? supabase.from('tecnico_estoque').update({ quantidade_minima: d.quantidade_minima }).eq('id', d.id)
        : supabase.from('tecnico_estoque').insert({ organizacao_id: organizacao.id, tecnico_id: d.tecnico_id, item_id: d.item_id, quantidade_minima: d.quantidade_minima })
      const { error } = await q
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}

// ---------------------------------------------------------------------------
// Ordens de serviço
// ---------------------------------------------------------------------------
export function useOrdens() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'ordens'],
    queryFn: async (): Promise<OrdemServico[]> => {
      const { data, error } = await supabase.from('ordens_servico').select('*').eq('organizacao_id', organizacao.id).order('criado_em', { ascending: false }).limit(300)
      if (error) throw error
      return (data ?? []).map((o) => ({ ...o, sinal_dbm: o.sinal_dbm == null ? null : Number(o.sinal_dbm) })) as OrdemServico[]
    },
  })
}

export function useOsMateriais(osId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'materiais', osId ?? 'x'],
    enabled: osId !== null,
    queryFn: async (): Promise<OsMaterial[]> => {
      const { data, error } = await supabase.from('os_materiais').select('*').eq('os_id', osId!)
      if (error) throw error
      return (data ?? []).map((m) => ({ ...m, quantidade: Number(m.quantidade), valor_unitario: Number(m.valor_unitario), valor_total: Number(m.valor_total) })) as OsMaterial[]
    },
  })
}

export function useOsHistorico(osId: string | null) {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'historico', osId ?? 'x'],
    enabled: osId !== null,
    queryFn: async (): Promise<OsHistorico[]> => {
      const { data, error } = await supabase.from('os_historico').select('*').eq('os_id', osId!).order('criado_em')
      if (error) throw error
      return (data ?? []) as OsHistorico[]
    },
  })
}

export function useOsCustoContratos() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'custo-contratos'],
    queryFn: async (): Promise<OsCustoContrato[]> => {
      const { data, error } = await supabase.from('vw_os_custo_contrato').select('contrato_id, chamados, custo_material').eq('organizacao_id', organizacao.id)
      if (error) throw error
      return (data ?? []).map((c) => ({ ...c, chamados: Number(c.chamados), custo_material: Number(c.custo_material) })) as OsCustoContrato[]
    },
  })
}

export interface DadosAbrirOs {
  negocio_id: string
  tipo: string
  descricao: string
  pessoa_id?: string | null
  contrato_id?: string | null
  tecnico_id?: string | null
  cto_id?: string | null
  prioridade?: string
  os_origem_id?: string | null
}

export function useAbrirOs() {
  const invalidar = useInvalidarOs()
  return useMutation({
    mutationFn: async (d: DadosAbrirOs) => {
      const { data, error } = await supabase.rpc('abrir_os', {
        p_negocio_id: d.negocio_id, p_tipo: d.tipo, p_descricao: d.descricao,
        p_pessoa_id: d.pessoa_id ?? null, p_contrato_id: d.contrato_id ?? null, p_tecnico_id: d.tecnico_id ?? null,
        p_cto_id: d.cto_id ?? null, p_prioridade: d.prioridade ?? 'normal', p_aberto_via: 'admin', p_os_origem_id: d.os_origem_id ?? null,
      })
      if (error) throw error
      return data as OrdemServico
    },
    onSuccess: invalidar,
  })
}

export const useAtualizarOs = () => useRpc<{ p_os_id: string; p_tecnico_id?: string | null; p_prioridade?: string | null; p_cto_id?: string | null; p_observacao?: string | null }>('atualizar_os')
export const useCienciaOs = () => useRpc<{ p_os_id: string }>('ciencia_os')
export const useAgendarOs = () => useRpc<{ p_os_id: string; p_data: string; p_hora: string }>('agendar_os')
export const useSolicitarRemarcacao = () => useRpc<{ p_os_id: string; p_data: string; p_hora: string; p_motivo: string }>('solicitar_remarcacao_os')
export const useResponderRemarcacao = () => useRpc<{ p_os_id: string; p_aprovar: boolean }>('responder_remarcacao_os')
export const useIniciarOs = () => useRpc<{ p_os_id: string }>('iniciar_os')
export const usePausarOs = () => useRpc<{ p_os_id: string; p_motivo: string }>('pausar_os')
export const useRetomarOs = () => useRpc<{ p_os_id: string }>('retomar_os')
export const useEncerrarOs = () => useRpc<{ p_os_id: string; p_itens: { item_id: string; quantidade: number }[]; p_diagnostico?: string | null; p_sinal_dbm?: number | null; p_observacao?: string | null }>('encerrar_os')
export const useCancelarOs = () => useRpc<{ p_os_id: string; p_motivo: string }>('cancelar_os')
export const useAvaliarOs = () => useRpc<{ p_os_id: string; p_resolvido: boolean; p_nota?: number | null }>('avaliar_os')
export const useAprovarComissao = () => useRpc<{ p_os_id: string; p_conta_id: string; p_vencimento: string; p_valor?: number | null }>('aprovar_comissao_os')

export interface ReposicaoPendente { id: string; tecnico_id: string; item_id: string; quantidade: number; criado_em: string }

export function useReposicoesPendentes() {
  const { organizacao } = useOrganizacao()
  return useQuery({
    queryKey: [...chave(organizacao.id), 'reposicoes'],
    queryFn: async (): Promise<ReposicaoPendente[]> => {
      const { data, error } = await supabase.from('reposicao_solicitacoes').select('id, tecnico_id, item_id, quantidade, criado_em').eq('organizacao_id', organizacao.id).eq('atendida', false).order('criado_em')
      if (error) throw error
      return (data ?? []).map((r) => ({ ...r, quantidade: Number(r.quantidade) })) as ReposicaoPendente[]
    },
  })
}

/** Cria o login do técnico (usuário/senha) sem derrubar a sessão do admin: usa um cliente auxiliar. */
export function useCriarLoginTecnico() {
  const invalidar = useInvalidarOs()
  return useMutation({
    mutationFn: async (d: { tecnico_id: string; login: string; senha: string; nome: string }) => {
      const login = d.login.trim().toLowerCase()
      if (!/^[a-z0-9._-]{3,30}$/.test(login)) throw new Error('Login inválido: use 3 a 30 letras minúsculas, números, ponto, hífen ou _.')
      if (d.senha.length < 8) throw new Error('Senha do técnico precisa de pelo menos 8 caracteres.')
      const aux = createClient(import.meta.env.VITE_SUPABASE_URL as string, import.meta.env.VITE_SUPABASE_ANON_KEY as string, { auth: { persistSession: false, autoRefreshToken: false } })
      const { data, error } = await aux.auth.signUp({ email: `${login}@tecnico.local`, password: d.senha, options: { data: { tecnico: 'true', nome: d.nome } } })
      if (error) throw error
      const usuarioId = data.user?.id
      if (!usuarioId) throw new Error('O Supabase não devolveu o usuário. Verifique se a confirmação de e-mail está DESLIGADA no projeto (Auth → Providers → Email).')
      await aux.auth.signOut().catch(() => undefined)
      const { error: eUp } = await supabase.from('tecnicos').update({ usuario_id: usuarioId, login }).eq('id', d.tecnico_id)
      if (eUp) throw eUp
    },
    onSuccess: invalidar,
  })
}
