import { useMemo, useState, type ChangeEvent } from 'react'
import { Link } from 'react-router'
import { useNegocios } from '../../negocios/api'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { Carregando } from '../../../core/ui/Carregando'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { mesAtualISO } from '../../../core/formatos'
import { documentoValido, somenteDigitos } from '../../pessoas/tipos'
import { CAMPOS, decodificar, lerCsv, montarLinhas, nomePlanoImportado, sugerirMapeamento, type ChaveCampo, type LinhaImportacao, type Mapeamento, type Tabela } from './csv'
import { lerXlsx } from './xlsx'
import { useImportarClientes, type ItemRelatorio, type RelatorioImportacao } from './api'

/** Validação local (mesmas regras do banco) só para orientar antes da simulação. */
function problemasLocais(l: LinhaImportacao): string[] {
  const p: string[] = []
  if (l.nome.trim().length < 2) p.push('nome')
  const doc = somenteDigitos(l.documento)
  if (doc && !documentoValido(doc)) p.push('CPF/CNPJ inválido')
  const tel = somenteDigitos(l.telefone)
  if (tel && (tel.length < 10 || tel.length > 13)) p.push('telefone')
  if (l.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(l.email.toLowerCase())) p.push('e-mail')
  const dia = somenteDigitos(l.dia_vencimento)
  if (dia && (Number(dia) < 1 || Number(dia) > 31)) p.push('dia de vencimento')
  if (l.data_inicio && !/^(\d{4}-\d{2}-\d{2}|\d{1,2}\/\d{1,2}\/\d{4})/.test(l.data_inicio)) p.push('data de início')
  if (l.data_fim && !/^(\d{4}-\d{2}-\d{2}|\d{1,2}\/\d{1,2}\/\d{4})/.test(l.data_fim)) p.push('data de cancelamento')
  return p
}

const TOM_STATUS: Record<ItemRelatorio['status'], 'ok' | 'alerta' | 'neutro'> = { importada: 'ok', rejeitada: 'alerta', ignorada: 'neutro' }
const ROTULO_STATUS: Record<ItemRelatorio['status'], string> = { importada: 'OK', rejeitada: 'Rejeitada', ignorada: 'Já existe' }

function Resumo({ r }: { r: RelatorioImportacao }) {
  const itens: [string, number][] = [
    ['Linhas', r.total], ['Importadas', r.importadas], ['Rejeitadas', r.rejeitadas], ['Já existentes', r.ignoradas],
    ['Pessoas novas', r.pessoas_novas], ['Pessoas reaproveitadas', r.pessoas_existentes], ['Planos criados', r.planos_novos],
    ['Contratos ativos', r.contratos_ativos], ['Contratos encerrados', r.contratos_encerrados],
  ]
  return (
    <dl className="grid grid-cols-3 gap-3 sm:grid-cols-5 lg:grid-cols-9">
      {itens.map(([k, v]) => (
        <div key={k} className="rounded-md border border-line bg-surface px-3 py-2">
          <dt className="text-xs text-ink-muted">{k}</dt>
          <dd className="text-lg font-semibold">{v}</dd>
        </div>
      ))}
    </dl>
  )
}

export function ImportarCsvPage() {
  const { organizacao } = useOrganizacao()
  const negociosQ = useNegocios()
  const importar = useImportarClientes()
  const [arquivo, setArquivo] = useState<string>('')
  const [tabela, setTabela] = useState<Tabela | null>(null)
  const [mapa, setMapa] = useState<Mapeamento | null>(null)
  const [negocioId, setNegocioId] = useState<string>('')
  const [faturarDesde, setFaturarDesde] = useState<string>(mesAtualISO())
  const [simulacao, setSimulacao] = useState<RelatorioImportacao | null>(null)
  const [resultado, setResultado] = useState<RelatorioImportacao | null>(null)
  const [erro, setErro] = useState<string | null>(null)

  const negocios = useMemo(() => (negociosQ.data ?? []).filter((n) => n.ativo), [negociosQ.data])
  const negocioPadrao = negocios.find((n) => n.slug === 'servnet' || /servnet/i.test(n.nome))?.id ?? negocios[0]?.id ?? ''
  const negocioAtual = negocioId || negocioPadrao

  const linhas = useMemo(() => (tabela && mapa ? montarLinhas(tabela, mapa) : []), [tabela, mapa])
  const problemas = useMemo(() => linhas.map(problemasLocais), [linhas])
  const faltando = mapa ? CAMPOS.filter((c) => c.obrigatorio && mapa[c.chave] === null).map((c) => c.rotulo) : []
  const prontas = linhas.length > 0 && faltando.length === 0
  const porLinha = useMemo(() => new Map((simulacao?.linhas ?? []).map((i) => [i.linha, i])), [simulacao])

  async function aoEscolherArquivo(e: ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0]
    if (!f) return
    setErro(null); setSimulacao(null); setResultado(null)
    try {
      const buffer = await f.arrayBuffer()
      const ehExcel = /\.xlsx?$/i.test(f.name)
      const t = ehExcel ? await lerXlsx(buffer) : lerCsv(decodificar(buffer))
      if (t.cabecalho.length < 2 || t.linhas.length === 0) throw new Error('O arquivo não tem cabeçalho e linhas de dados.')
      setArquivo(f.name); setTabela(t); setMapa(sugerirMapeamento(t.cabecalho))
    } catch (err) {
      setTabela(null); setMapa(null); setErro(err instanceof Error ? err.message : 'Não foi possível ler o arquivo.')
    }
  }

  function mudarMapa(chave: ChaveCampo, valor: string) {
    setMapa((m) => (m ? { ...m, [chave]: valor === '' ? null : Number(valor) } : m))
    setSimulacao(null); setResultado(null)
  }

  async function executar(simular: boolean) {
    setErro(null)
    try {
      const r = await importar.mutateAsync({ negocioId: negocioAtual, linhas, simular, faturarDesde: faturarDesde || null })
      if (simular) setSimulacao(r); else setResultado(r)
    } catch (err) {
      setErro(mensagemDeErro(err))
    }
  }

  const colunas = tabela ? [{ valor: '', rotulo: '— não importar —' }, ...tabela.cabecalho.map((c, i) => ({ valor: String(i), rotulo: c || `Coluna ${i + 1}` }))] : []

  return (
    <>
      <CabecalhoPagina
        titulo="Importar clientes"
        descricao="Clientes, planos e contratos do sistema anterior para um negócio. Nada é gravado antes da confirmação."
        acoes={<Link to="/configuracoes" className="text-sm text-brand-700 hover:underline">Voltar às configurações</Link>}
      />
      {erro && <div className="mb-4"><Alerta tipo="erro">{erro}</Alerta></div>}

      {resultado ? (
        <Cartao>
          <h2 className="mb-1 text-lg font-semibold">Importação concluída</h2>
          <p className="mb-4 text-sm text-ink-muted">Negócio {resultado.negocio} · arquivo {arquivo}</p>
          <Resumo r={resultado} />
          {resultado.rejeitadas > 0 && (
            <div className="mt-4">
              <h3 className="mb-2 text-sm font-semibold">Linhas rejeitadas</h3>
              <ul className="space-y-1 text-sm">
                {resultado.linhas.filter((l) => l.status === 'rejeitada').map((l) => (
                  <li key={l.linha}><span className="font-mono text-ink-muted">linha {l.linha}</span> · {l.motivo}</li>
                ))}
              </ul>
            </div>
          )}
          <div className="mt-6 flex gap-2">
            <Link to="/contratos"><Botao>Ver contratos</Botao></Link>
            <Botao variante="secundario" onClick={() => { setResultado(null); setSimulacao(null); setTabela(null); setMapa(null); setArquivo('') }}>Importar outro arquivo</Botao>
          </div>
        </Cartao>
      ) : (
        <div className="space-y-6">
          <Cartao>
            <h2 className="mb-4 text-sm font-semibold uppercase tracking-wide text-ink-muted">1. Arquivo e destino</h2>
            {negociosQ.isPending ? <Carregando /> : negocios.length === 0 ? (
              <Alerta tipo="info">Cadastre um negócio ativo (ex.: SERVNET) antes de importar.</Alerta>
            ) : (
              <div className="grid gap-4 md:grid-cols-3">
                <Selecao rotulo="Negócio de destino" opcoes={negocios.map((n) => ({ valor: n.id, rotulo: n.nome }))} value={negocioAtual} onChange={(e) => { setNegocioId(e.target.value); setSimulacao(null) }} />
                <Campo rotulo="Faturar contratos ativos a partir de" type="date" value={faturarDesde} onChange={(e) => { setFaturarDesde(e.target.value); setSimulacao(null) }} />
                <Campo rotulo="Arquivo CSV ou Excel (.xlsx)" type="file" accept=".csv,.xlsx,.xls,text/csv,text/plain,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" onChange={aoEscolherArquivo} className="py-1.5" />
              </div>
            )}
            <p className="mt-3 text-xs text-ink-muted">
              Cobranças anteriores à data "faturar a partir de" não são geradas (já foram cobradas no sistema anterior). Deixe em branco para faturar desde o início de cada contrato.
            </p>
          </Cartao>

          {tabela && mapa && (
            <Cartao>
              <h2 className="mb-1 text-sm font-semibold uppercase tracking-wide text-ink-muted">2. Colunas</h2>
              <p className="mb-4 text-sm text-ink-muted">{arquivo}: {tabela.linhas.length} linha(s), {tabela.cabecalho.length} coluna(s), separador "{tabela.separador === '\t' ? 'tabulação' : tabela.separador}". Confira o mapeamento sugerido.</p>
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {CAMPOS.map((c) => (
                  <Selecao key={c.chave} rotulo={c.rotulo + (c.obrigatorio ? ' *' : '')} opcoes={colunas} value={mapa[c.chave] === null ? '' : String(mapa[c.chave])} onChange={(e) => mudarMapa(c.chave, e.target.value)} />
                ))}
              </div>
              {faltando.length > 0 && <div className="mt-4"><Alerta tipo="erro">Mapeie as colunas obrigatórias: {faltando.join(', ')}.</Alerta></div>}
            </Cartao>
          )}

          {prontas && (
            <Cartao>
              <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
                <div>
                  <h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">3. Pré-visualização</h2>
                  <p className="text-sm text-ink-muted">
                    {simulacao
                      ? `Simulação: ${simulacao.importadas} para importar, ${simulacao.rejeitadas} rejeitada(s), ${simulacao.ignoradas} já existente(s).`
                      : `${problemas.filter((p) => p.length === 0).length} linha(s) sem problemas locais, ${problemas.filter((p) => p.length > 0).length} com pendências. Simule para validar no servidor.`}
                  </p>
                </div>
                <div className="flex gap-2">
                  <Botao variante="secundario" onClick={() => executar(true)} carregando={importar.isPending && !simulacao}>Simular importação</Botao>
                  <Botao onClick={() => executar(false)} disabled={!simulacao || simulacao.importadas === 0} carregando={importar.isPending && !!simulacao}>
                    {simulacao ? `Importar ${simulacao.importadas} linha(s)` : 'Importar'}
                  </Botao>
                </div>
              </div>
              {simulacao && <div className="mb-4"><Resumo r={simulacao} /></div>}
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                    <tr><th className="py-2 pr-3">Linha</th><th className="py-2 pr-3">Nome</th><th className="py-2 pr-3">CPF/CNPJ</th><th className="py-2 pr-3">Telefone</th><th className="py-2 pr-3">Plano</th><th className="py-2 pr-3">Valor</th><th className="py-2 pr-3">Venc.</th><th className="py-2 pr-3">Início</th><th className="py-2 pr-3">Cancelamento</th><th className="py-2">Situação</th></tr>
                  </thead>
                  <tbody className="divide-y divide-line">
                    {linhas.map((l, i) => {
                      const s = porLinha.get(l.linha)
                      const locais = problemas[i]
                      return (
                        <tr key={l.linha} className={s?.status === 'rejeitada' || (!s && locais.length) ? 'bg-amber-50/40' : ''}>
                          <td className="py-2 pr-3 font-mono text-ink-muted">{l.linha}</td>
                          <td className="py-2 pr-3">{l.nome || '—'}</td>
                          <td className="py-2 pr-3 whitespace-nowrap">{l.documento || '—'}</td>
                          <td className="py-2 pr-3 whitespace-nowrap">{l.telefone || '—'}</td>
                          <td className="py-2 pr-3 whitespace-nowrap">{nomePlanoImportado(l.plano) || '—'}</td>
                          <td className="py-2 pr-3 whitespace-nowrap">{l.valor || 'tabela'}</td>
                          <td className="py-2 pr-3">{l.dia_vencimento || '—'}</td>
                          <td className="py-2 pr-3 whitespace-nowrap">{l.data_inicio || '—'}</td>
                          <td className="py-2 pr-3 whitespace-nowrap">{l.data_fim || '—'}</td>
                          <td className="py-2">
                            {s ? (
                              <span className="inline-flex flex-wrap items-center gap-1">
                                <Distintivo tom={TOM_STATUS[s.status]}>{ROTULO_STATUS[s.status]}</Distintivo>
                                {s.status === 'importada' && s.pessoa === 'existente' && <Distintivo tom="info">pessoa existente</Distintivo>}
                                {s.status === 'importada' && s.plano === 'novo' && <Distintivo tom="info">plano novo</Distintivo>}
                                {s.status === 'importada' && s.contrato === 'encerrado' && <Distintivo tom="neutro">encerrado</Distintivo>}
                                {s.motivo && <span className="text-xs text-ink-muted">{s.motivo}</span>}
                              </span>
                            ) : locais.length ? (
                              <span className="inline-flex flex-wrap items-center gap-1"><Distintivo tom="alerta">Verificar</Distintivo><span className="text-xs text-ink-muted">{locais.join(', ')}</span></span>
                            ) : <Distintivo tom="neutro">Pronta</Distintivo>}
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
              <p className="mt-3 text-xs text-ink-muted">Organização: {organizacao.nome}. Linhas rejeitadas não impedem as demais: cada linha é gravada ou desfeita por inteiro.</p>
            </Cartao>
          )}
        </div>
      )}
    </>
  )
}
