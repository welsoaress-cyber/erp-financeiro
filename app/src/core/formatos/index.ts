const moedaBRL = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })
const dataBR = new Intl.DateTimeFormat('pt-BR', { timeZone: 'UTC' })

export function formatarMoeda(valor: number | string): string {
  return moedaBRL.format(typeof valor === 'string' ? Number(valor) : valor)
}

/** Recebe 'AAAA-MM-DD' (date do Postgres) e devolve 'DD/MM/AAAA' sem deslocamento de fuso. */
export function formatarData(iso: string): string {
  return dataBR.format(new Date(`${iso}T00:00:00Z`))
}

export function hojeISO(): string {
  const d = new Date()
  const mes = String(d.getMonth() + 1).padStart(2, '0')
  const dia = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${mes}-${dia}`
}
