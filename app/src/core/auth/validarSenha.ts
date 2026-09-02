export const REGRAS_SENHA = [
  { id: 'tamanho', texto: 'No mínimo 8 caracteres', ok: (s: string) => s.length >= 8, erro: 'A senha deve ter no mínimo 8 caracteres.' },
  { id: 'maiuscula', texto: '1 letra maiúscula', ok: (s: string) => /[A-ZÀ-Ý]/.test(s), erro: 'A senha deve conter pelo menos 1 letra maiúscula.' },
  { id: 'minuscula', texto: '1 letra minúscula', ok: (s: string) => /[a-zà-ÿ]/.test(s), erro: 'A senha deve conter pelo menos 1 letra minúscula.' },
  { id: 'numero', texto: '1 número', ok: (s: string) => /\d/.test(s), erro: 'A senha deve conter pelo menos 1 número.' },
] as const

/** Devolve a lista de erros da senha; lista vazia = senha aceita. Caractere especial é recomendado, não exigido. */
export function validarSenha(senha: string): string[] {
  return REGRAS_SENHA.filter((r) => !r.ok(senha)).map((r) => r.erro)
}

export function temCaractereEspecial(senha: string): boolean {
  return /[^A-Za-z0-9À-ÿ]/.test(senha)
}
