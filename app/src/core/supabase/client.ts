import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const supabaseConfigurado = Boolean(url && anonKey)

/**
 * Cliente único do Supabase. Se as variáveis não estiverem definidas, o app
 * exibe uma tela de configuração em vez de falhar silenciosamente.
 */
export const supabase = createClient(
  url ?? 'http://localhost',
  anonKey ?? 'nao-configurado',
  { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } },
)
