const TRADUCOES: Array<[RegExp, string]> = [
  [/invalid login credentials/i, 'E-mail ou senha inválidos.'],
  [/email not confirmed/i, 'E-mail ainda não confirmado. Verifique sua caixa de entrada.'],
  [/user already registered/i, 'Já existe uma conta com este e-mail.'],
  [/password should be at least/i, 'A senha deve ter pelo menos 6 caracteres.'],
  [/rate limit|too many requests/i, 'Muitas tentativas. Aguarde alguns instantes.'],
]

function hostDoServidor(): string {
  try { return new URL(import.meta.env.VITE_SUPABASE_URL).host } catch { return 'servidor não configurado' }
}

/** Converte qualquer erro em uma mensagem curta e legível em português. */
export function mensagemDeErro(erro: unknown, padrao = 'Ocorreu um erro inesperado.'): string {
  const texto =
    erro instanceof Error ? erro.message
    : typeof erro === 'string' ? erro
    : (erro as { message?: string } | null)?.message ?? ''
  if (/failed to fetch|network|fetch failed/i.test(texto)) return `Sem conexão com o servidor (${hostDoServidor()}).`
  for (const [regex, msg] of TRADUCOES) if (regex.test(texto)) return msg
  return texto || padrao
}
