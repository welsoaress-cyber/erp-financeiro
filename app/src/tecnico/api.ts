import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../core/supabase/client'
import type { OrdemServico, OsHistorico, OsMaterial, Tecnico, TecnicoEstoque } from '../modules/os/tipos'
import type { EstoqueItem } from '../modules/estoque/tipos'

// Hooks do TÉCNICO logado: sem organização (a RLS devolve só o que é dele).
const CHAVE = ['tecnico-app'] as const

function useInvalidarTecnico() {
  const qc = useQueryClient()
  return () => void qc.invalidateQueries({ queryKey: CHAVE })
}

export function useMeuTecnico() {
  return useQuery({
    queryKey: [...CHAVE, 'eu'],
    queryFn: async (): Promise<Tecnico | null> => {
      const { data, error } = await supabase.from('tecnicos').select('*').limit(1).maybeSingle()
      if (error) throw error
      return (data as Tecnico | null) ?? null
    },
  })
}

export function useMeusChamados() {
  return useQuery({
    queryKey: [...CHAVE, 'chamados'],
    refetchInterval: 60_000,
    queryFn: async (): Promise<OrdemServico[]> => {
      const { data, error } = await supabase.from('ordens_servico').select('*').order('criado_em', { ascending: false }).limit(100)
      if (error) throw error
      return (data ?? []) as OrdemServico[]
    },
  })
}

export function useMinhaBolsa() {
  return useQuery({
    queryKey: [...CHAVE, 'bolsa'],
    queryFn: async (): Promise<TecnicoEstoque[]> => {
      const { data, error } = await supabase.from('tecnico_estoque').select('*')
      if (error) throw error
      return (data ?? []).map((b) => ({ ...b, quantidade: Number(b.quantidade), quantidade_minima: Number(b.quantidade_minima) })) as TecnicoEstoque[]
    },
  })
}

export function useItensDoNegocio() {
  return useQuery({
    queryKey: [...CHAVE, 'itens'],
    queryFn: async (): Promise<EstoqueItem[]> => {
      const { data, error } = await supabase.from('estoque_itens').select('*').eq('ativo', true).order('nome')
      if (error) throw error
      return (data ?? []) as EstoqueItem[]
    },
  })
}

export interface InfoCliente { cliente: string | null; telefone: string | null; endereco: string | null; contrato: string | null; cto: string | null }

export function useInfoCliente(osId: string | null) {
  return useQuery({
    queryKey: [...CHAVE, 'cliente', osId ?? 'x'],
    enabled: osId !== null,
    queryFn: async (): Promise<InfoCliente | null> => {
      const { data, error } = await supabase.rpc('os_info_cliente', { p_os_id: osId! })
      if (error) throw error
      const linha = Array.isArray(data) ? data[0] : data
      return (linha as InfoCliente | undefined) ?? null
    },
  })
}

export function useMateriaisOs(osId: string | null) {
  return useQuery({
    queryKey: [...CHAVE, 'materiais', osId ?? 'x'],
    enabled: osId !== null,
    queryFn: async (): Promise<OsMaterial[]> => {
      const { data, error } = await supabase.from('os_materiais').select('*').eq('os_id', osId!)
      if (error) throw error
      return (data ?? []).map((m) => ({ ...m, quantidade: Number(m.quantidade), valor_unitario: Number(m.valor_unitario), valor_total: Number(m.valor_total) })) as OsMaterial[]
    },
  })
}

export function useHistoricoOs(osId: string | null) {
  return useQuery({
    queryKey: [...CHAVE, 'historico', osId ?? 'x'],
    enabled: osId !== null,
    queryFn: async (): Promise<OsHistorico[]> => {
      const { data, error } = await supabase.from('os_historico').select('*').eq('os_id', osId!).order('criado_em')
      if (error) throw error
      return (data ?? []) as OsHistorico[]
    },
  })
}

function useRpcTecnico<T extends Record<string, unknown>>(fn: string) {
  const invalidar = useInvalidarTecnico()
  return useMutation({
    mutationFn: async (params: T) => {
      const { data, error } = await supabase.rpc(fn, params)
      if (error) throw error
      return data as unknown
    },
    onSuccess: invalidar,
  })
}

export const useCiencia = () => useRpcTecnico<{ p_os_id: string }>('ciencia_os')
export const useAgendar = () => useRpcTecnico<{ p_os_id: string; p_data: string; p_hora: string }>('agendar_os')
export const useSolicitarRemarcacaoTec = () => useRpcTecnico<{ p_os_id: string; p_data: string; p_hora: string; p_motivo: string }>('solicitar_remarcacao_os')
export const useIniciar = () => useRpcTecnico<{ p_os_id: string }>('iniciar_os')
export const usePausar = () => useRpcTecnico<{ p_os_id: string; p_motivo: string }>('pausar_os')
export const useRetomar = () => useRpcTecnico<{ p_os_id: string }>('retomar_os')
export const useEncerrar = () => useRpcTecnico<{ p_os_id: string; p_itens: { item_id: string; quantidade: number }[]; p_diagnostico?: string | null; p_sinal_dbm?: number | null; p_observacao?: string | null; p_equipamentos?: { item_id: string; numero_serie: string }[] }>('encerrar_os')
export const usePerdaMinha = () => useRpcTecnico<{ p_tecnico_id: string; p_item_id: string; p_quantidade: number; p_avaria: boolean; p_motivo: string; p_defeito_fabrica?: boolean }>('perda_tecnico')
export const usePedirReposicao = () => useRpcTecnico<{ p_item_id: string; p_quantidade: number }>('solicitar_reposicao')

/** Reduz a foto para no máximo 1280px (JPEG 0,8) antes de subir. */
async function comprimirFoto(arquivo: File): Promise<Blob> {
  const bitmap = await createImageBitmap(arquivo)
  const escala = Math.min(1, 1280 / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(bitmap.width * escala)
  canvas.height = Math.round(bitmap.height * escala)
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  return await new Promise((resolver, rejeitar) => canvas.toBlob((b) => (b ? resolver(b) : rejeitar(new Error('Falha ao processar a foto.'))), 'image/jpeg', 0.8))
}

export function useEnviarFoto() {
  const invalidar = useInvalidarTecnico()
  return useMutation({
    mutationFn: async (d: { os_id: string; arquivo: File }) => {
      const blob = await comprimirFoto(d.arquivo)
      const caminho = `os/${d.os_id}/${Date.now()}.jpg`
      const { error: eUp } = await supabase.storage.from('os-fotos').upload(caminho, blob, { contentType: 'image/jpeg' })
      if (eUp) throw eUp
      const { error } = await supabase.rpc('registrar_foto_os', { p_os_id: d.os_id, p_caminho: caminho })
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}

export function useFotosOs(osId: string | null) {
  return useQuery({
    queryKey: [...CHAVE, 'fotos', osId ?? 'x'],
    enabled: osId !== null,
    queryFn: async (): Promise<{ id: string; caminho: string; url: string }[]> => {
      const { data, error } = await supabase.from('os_fotos').select('id, caminho').eq('os_id', osId!)
      if (error) throw error
      const fotos = data ?? []
      if (fotos.length === 0) return []
      const { data: urls, error: eUrl } = await supabase.storage.from('os-fotos').createSignedUrls(fotos.map((f) => f.caminho), 3600)
      if (eUrl) throw eUrl
      return fotos.map((f, i) => ({ ...f, url: urls?.[i]?.signedUrl ?? '' }))
    },
  })
}
