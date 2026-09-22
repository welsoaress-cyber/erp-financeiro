/** O app pode morar num subcaminho (ex.: servnet.net.br/painel) — vite.config.ts define `base`.
 *  Use pra montar link absoluto (WhatsApp, e-mail, QR code) fora do router (que já lida com isso via basename). */
export function linkAbsoluto(caminho: string): string {
  return `${window.location.origin}${import.meta.env.BASE_URL}${caminho}`
}
