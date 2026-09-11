import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../core/supabase/client'
import { useAuth } from '../core/auth/useAuth'
import type { AvisoRede, ContratoCliente, Fatura, Fidelidade, Indicacao, Pagamento, PortalResumo, Promocao, ProximaFatura, Solicitacao, TipoSolicitacao } from './tipos'

const chave = (u: string | undefined) => ['portal', u ?? ''] as const
const num = <T extends object>(rows: T[], campos: (keyof T)[]) => rows.map((r) => { const c = { ...r } as Record<keyof T, unknown>; for (const k of campos) c[k] = Number(c[k]); return c as T })

export function usePortalResumo() {
  const { usuario } = useAuth()
  return useQuery({
    queryKey: [...chave(usuario?.id), 'resumo'],
    enabled: Boolean(usuario),
    queryFn: async (): Promise<PortalResumo | null> => {
      const { data, error } = await supabase.rpc('portal_resumo')
      if (error) throw error
      if (!data) return null
      const r = data as PortalResumo
      return { ...r, em_aberto: Number(r.em_aberto), vencidas: Number(r.vencidas), contratos_ativos: Number(r.contratos_ativos), indicacoes_convertidas: Number(r.indicacoes_convertidas) }
    },
  })
}
function useLista<T extends object>(nome: string, fn: string, campos: (keyof T)[]) {
  const { usuario } = useAuth()
  return useQuery({
    queryKey: [...chave(usuario?.id), nome],
    enabled: Boolean(usuario),
    queryFn: async (): Promise<T[]> => { const { data, error } = await supabase.rpc(fn); if (error) throw error; return num((data ?? []) as T[], campos) },
  })
}
export const useFaturas = () => useLista<Fatura>('faturas', 'portal_faturas', ['valor'])
export const useProximasFaturas = () => useLista<ProximaFatura>('proximas', 'portal_proximas_faturas', ['valor'])
export const usePagamentos = () => useLista<Pagamento>('pagamentos', 'portal_pagamentos', ['valor'])
export const useContratosCliente = () => useLista<ContratoCliente>('contratos', 'portal_contratos', ['valor', 'descontos_pendentes'])
export const usePromocoesCliente = () => useLista<Promocao>('promocoes', 'portal_promocoes', [])
export const useIndicacoesCliente = () => useLista<Indicacao>('indicacoes', 'portal_indicacoes', ['beneficio_valor'])

function useInvalidarPortal() {
  const { usuario } = useAuth(); const qc = useQueryClient()
  return () => qc.invalidateQueries({ queryKey: chave(usuario?.id) })
}
export function useVincularPortal() {
  const invalidar = useInvalidarPortal()
  return useMutation({
    mutationFn: async (p: { documento: string; telefone: string }) => {
      const { data, error } = await supabase.rpc('portal_vincular', { p_documento: p.documento, p_telefone: p.telefone })
      if (error) throw error
      return data as { pessoa_id: string; codigo_indicacao: string; ja_vinculado: boolean }
    },
    onSuccess: invalidar,
  })
}
export function useIndicar() {
  const invalidar = useInvalidarPortal()
  return useMutation({
    mutationFn: async (p: { negocioId: string; nome: string; telefone: string }) => {
      const { error } = await supabase.rpc('portal_indicar', { p_negocio_id: p.negocioId, p_nome: p.nome, p_telefone: p.telefone })
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}
/** Página pública do link de indicação (sem login). */
export function useInfoIndicacao(codigo: string) {
  return useQuery({
    queryKey: ['portal-publico', codigo],
    queryFn: async (): Promise<{ negocio: string; texto: string | null; cor: string; logo: string | null; indicador: string } | null> => {
      const { data, error } = await supabase.rpc('portal_info_indicacao', { p_codigo: codigo })
      if (error) throw error
      return data ?? null
    },
  })
}
export function useIndicacaoPublica() {
  return useMutation({
    mutationFn: async (p: { codigo: string; nome: string; telefone: string }) => {
      const { data, error } = await supabase.rpc('portal_indicacao_publica', { p_codigo: p.codigo, p_nome: p.nome, p_telefone: p.telefone })
      if (error) throw error
      return data as { ok: boolean; negocio: string; repetida: boolean }
    },
  })
}

// ---- Etapa 11B: portal estilo SERVNET ----
export const useFidelidade = () => useLista<Fidelidade>('fidelidade', 'portal_fidelidade', ['valor', 'selos', 'ciclo'])
export const useStatusRede = () => useLista<AvisoRede>('rede', 'portal_status_rede', [])
export const useSolicitacoes = () => useLista<Solicitacao>('solicitacoes', 'portal_solicitacoes_cliente', [])
export function useSolicitar() {
  const invalidar = useInvalidarPortal()
  return useMutation({
    mutationFn: async (p: { negocioId: string; tipo: TipoSolicitacao; descricao: string; contratoId?: string | null }) => {
      const { data, error } = await supabase.rpc('portal_solicitar', { p_negocio_id: p.negocioId, p_tipo: p.tipo, p_descricao: p.descricao || null, p_contrato_id: p.contratoId ?? null })
      if (error) throw error
      return data as { protocolo: string }
    },
    onSuccess: invalidar,
  })
}
export function useAtualizarContato() {
  const invalidar = useInvalidarPortal()
  return useMutation({
    mutationFn: async (p: { email: string; telefone: string; receberAvisos: boolean }) => {
      const { error } = await supabase.rpc('portal_atualizar_contato', { p_email: p.email || null, p_telefone: p.telefone, p_receber_avisos: p.receberAvisos })
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}
/** Login sem senha (CPF/CNPJ + nascimento): Edge Function portal-login devolve um token de link mágico, trocado por sessão aqui. */
export function useLoginSemSenha() {
  return useMutation({
    mutationFn: async (p: { documento: string; nascimento: string }) => {
      const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/portal-login`
      const res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: import.meta.env.VITE_SUPABASE_ANON_KEY }, body: JSON.stringify(p) })
      const corpo = (await res.json().catch(() => ({}))) as { ok?: boolean; msg?: string; token_hash?: string }
      if (!res.ok || !corpo.ok || !corpo.token_hash) throw new Error(corpo.msg ?? 'Não foi possível entrar. Tente novamente.')
      const { error } = await supabase.auth.verifyOtp({ token_hash: corpo.token_hash, type: 'magiclink' })
      if (error) throw error
    },
  })
}

// ---------------------------------------------------------------------------
// Visitas técnicas (Ordens de Serviço) — etapa 29C
// ---------------------------------------------------------------------------
export interface VisitaTecnica {
  id: string
  numero: string
  tipo: string
  status: 'aberto' | 'em_atendimento' | 'pausado' | 'encerrado' | 'cancelado'
  descricao: string
  data_agendada: string | null
  hora_agendada: string | null
  remarcacao_data: string | null
  remarcacao_hora: string | null
  remarcacao_motivo: string | null
  tecnico: string | null
  avaliacao_resolvido: boolean | null
  avaliacao_nota: number | null
  aberto_via: string
  criado_em: string
}

export const useVisitas = () => useLista<VisitaTecnica>('visitas', 'portal_minhas_visitas', [])

export function useAbrirVisita() {
  const invalidar = useInvalidarPortal()
  return useMutation({
    mutationFn: async (p: { negocioId: string; problema: string; descricao: string }) => {
      const { data, error } = await supabase.rpc('portal_abrir_visita', { p_negocio_id: p.negocioId, p_problema: p.problema, p_descricao: p.descricao || null })
      if (error) throw error
      const linha = Array.isArray(data) ? data[0] : data
      return linha as { numero: string; tecnico: string | null }
    },
    onSuccess: invalidar,
  })
}

export function useResponderRemarcacaoVisita() {
  const invalidar = useInvalidarPortal()
  return useMutation({
    mutationFn: async (p: { osId: string; aprovar: boolean }) => {
      const { error } = await supabase.rpc('portal_responder_remarcacao', { p_os_id: p.osId, p_aprovar: p.aprovar })
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}

export function useAvaliarVisita() {
  const invalidar = useInvalidarPortal()
  return useMutation({
    mutationFn: async (p: { osId: string; resolvido: boolean; nota?: number | null; reabrir?: boolean }) => {
      const { error } = await supabase.rpc('portal_avaliar_visita', { p_os_id: p.osId, p_resolvido: p.resolvido, p_nota: p.nota ?? null, p_reabrir: p.reabrir ?? false })
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}

// ---------------------------------------------------------------------------
// Pix (etapa 31)
// ---------------------------------------------------------------------------
export interface PixGerado { copia_cola: string; ticket_url?: string | null }

export function usePagarComPix() {
  return useMutation({
    mutationFn: async (p: { lancamentoId: string }): Promise<PixGerado> => {
      // reaproveita cobrança pendente antes de gerar outra
      const { data: existente } = await supabase.rpc('portal_pix_cobranca', { p_lancamento_id: p.lancamentoId })
      const ex = Array.isArray(existente) ? existente[0] : existente
      if (ex?.status === 'pendente' && ex.copia_cola) return { copia_cola: ex.copia_cola, ticket_url: ex.ticket_url }
      const { data, error } = await supabase.functions.invoke('pix-gerar', { body: { lancamento_id: p.lancamentoId } })
      if (error) {
        const detalhe = await (error as { context?: Response }).context?.json?.().catch(() => null)
        throw new Error(detalhe?.erro ?? 'Não foi possível gerar o Pix agora. Tente de novo ou fale com o suporte.')
      }
      if (!data?.ok) throw new Error(data?.erro ?? 'Não foi possível gerar o Pix.')
      return { copia_cola: data.copia_cola, ticket_url: data.ticket_url }
    },
  })
}

// ---------------------------------------------------------------------------
// Aceite digital do contrato (etapa 36)
// ---------------------------------------------------------------------------
export interface MeuAceite { contrato_id: string; codigo: number; negocio: string; plano: string; aceito: boolean; data_aceite: string | null }

export const useMeusAceites = () => useLista<MeuAceite>('aceites', 'portal_meus_aceites', [])

export function useTermoContrato(contratoId: string | null) {
  const { usuario } = useAuth()
  return useQuery({
    queryKey: [...chave(usuario?.id), 'termo', contratoId ?? 'x'],
    enabled: contratoId !== null,
    queryFn: async (): Promise<string> => {
      const { data, error } = await supabase.rpc('contrato_texto_termo', { p_contrato_id: contratoId! })
      if (error) throw error
      return data as string
    },
  })
}

export function useAceitarContrato() {
  const invalidar = useInvalidarPortal()
  return useMutation({
    mutationFn: async (p: { contratoId: string }) => {
      const { data, error } = await supabase.functions.invoke('portal-aceite', { body: { contrato_id: p.contratoId } })
      if (error) {
        const detalhe = await (error as { context?: Response }).context?.json?.().catch(() => null)
        throw new Error(detalhe?.erro ?? 'Não foi possível registrar o aceite agora.')
      }
      if (!data?.ok) throw new Error(data?.erro ?? 'Não foi possível registrar o aceite.')
    },
    onSuccess: invalidar,
  })
}
