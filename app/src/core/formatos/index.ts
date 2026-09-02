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

const mesBR = new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric', timeZone: 'UTC' })

/** Primeiro dia do mês de uma data ISO ('AAAA-MM-DD') → 'AAAA-MM-01'. */
export function inicioDoMes(iso: string): string {
  return `${iso.slice(0, 7)}-01`
}

export function mesAtualISO(): string {
  return inicioDoMes(hojeISO())
}

/** Soma meses a um 'AAAA-MM-01' sem problemas de fuso. */
export function somarMeses(mesISO: string, n: number): string {
  const [ano, mes] = mesISO.split('-').map(Number)
  const d = new Date(Date.UTC(ano, mes - 1 + n, 1))
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-01`
}

/** Último dia do mês de um 'AAAA-MM-01'. */
export function fimDoMes(mesISO: string): string {
  const [ano, mes] = mesISO.split('-').map(Number)
  const d = new Date(Date.UTC(ano, mes, 0))
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`
}

export function formatarMes(mesISO: string): string {
  const texto = mesBR.format(new Date(`${mesISO}T00:00:00Z`))
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}
