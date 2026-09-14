import { useMemo, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Carregando } from '../../../core/ui/Carregando'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMes, formatarMoeda, hojeISO, inicioDoMes, mesAtualISO } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { useCentrosCusto } from '../../centros_custo/api'
import { ROTULO_TIPO_CENTRO } from '../../centros_custo/tipos'
import { usePessoas } from '../../pessoas/api'
import { useCategorias } from '../../categorias/api'
import { useContas } from '../../contas/api'
import { ROTULO_STATUS, ROTULO_TIPO } from '../../lancamentos/tipos'
import { relatorioPorId, type Coluna, type Linha, type Relatorio } from '../catalogo'
import { useExecutarRelatorio, useFavoritos, useSalvarFavorito, type Favorito, type Filtros } from '../api'

const ROTULOS: Record<string, string> = { ...ROTULO_STATUS, ...ROTULO_TIPO, ...ROTULO_TIPO_CENTRO, operacional: 'Operacional', investimento: 'Investimento', ativo: 'Ativo', suspenso: 'Suspenso', encerrado: 'Encerrado' }

function formatar(v: unknown, c: Coluna): string {
  if (v == null || v === '') return '—'
  switch (c.tipo) {
    case 'moeda': return formatarMoeda(Number(v))
    case 'data': return formatarData(String(v).slice(0, 10))
    case 'mes': return formatarMes(String(v).slice(0, 7))
    case 'numero': return String(v)
    default: return ROTULOS[String(v)] ?? String(v)
  }
}

function csvDe(colunas: Coluna[], linhas: Linha[]): string {
  const esc = (s: string) => (/[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s)
  const cel = (l: Linha, c: Coluna) => {
    const v = l[c.chave]
    if (v == null) return ''
    if (c.tipo === 'moeda') return Number(v).toFixed(2).replace('.', ',')
    if (c.tipo === 'data') return formatarData(String(v).slice(0, 10))
    return esc(ROTULOS[String(v)] ?? String(v))
  }
  return [colunas.map((c) => c.rotulo).join(';'), ...linhas.map((l) => colunas.map((c) => cel(l, c)).join(';'))].join('\n')
}

/** Tela genérica: lê o catálogo, monta filtros, executa a view, ordena/agrupa/totaliza no navegador. */
export function RelatorioPage() {
  const { id = '' } = useParams()
  const [params] = useSearchParams()
  const rel = relatorioPorId(id)
  const favoritos = useFavoritos()
  const favId = params.get('f')
  if (!rel) return <Alerta tipo="erro">Relatório não encontrado. <Link to="/relatorios" className="underline">Voltar</Link></Alerta>
  if (favId && favoritos.isPending) return <Carregando texto="Abrindo favorito…" />
  const fav = favId ? favoritos.data?.find((x) => x.id === favId) : undefined
  // key: trocar de favorito remonta a tela com os filtros salvos como estado inicial
  return <RelatorioConteudo key={fav?.id ?? 'novo'} rel={rel} favorito={fav} />
}

function RelatorioConteudo({ rel, favorito }: { rel: Relatorio; favorito?: Favorito }) {
  const negocios = useNegocios()
  const centros = useCentrosCusto()
  const pessoas = usePessoas()
  const categorias = useCategorias()
  const contas = useContas()
  const salvar = useSalvarFavorito()

  const [filtros, setFiltros] = useState<Filtros>(() => ({ mes: mesAtualISO(), de: inicioDoMes(hojeISO()), ate: hojeISO(), ...(favorito?.filtros ?? {}) }))
  const [gerado, setGerado] = useState(Boolean(favorito))
  const [ordem, setOrdem] = useState<{ chave: string; desc: boolean } | null>(rel.ordem ? { chave: rel.ordem.chave, desc: Boolean(rel.ordem.desc) } : null)
  const [grupo, setGrupo] = useState('')
  const [nomeFav, setNomeFav] = useState('')

  const exec = useExecutarRelatorio(rel, filtros, gerado)
  const def = (k: string, v: string) => { setFiltros((f) => ({ ...f, [k]: v })); setGerado(false) }

  const linhas = useMemo(() => {
    const base = [...(exec.data ?? [])]
    if (!ordem) return base
    const c = rel.colunas.find((x) => x.chave === ordem.chave)
    const numerico = c?.tipo === 'moeda' || c?.tipo === 'numero'
    base.sort((a, b) => {
      const x = a[ordem.chave], y = b[ordem.chave]
      const r = numerico ? Number(x ?? 0) - Number(y ?? 0) : String(x ?? '').localeCompare(String(y ?? ''), 'pt-BR')
      return ordem.desc ? -r : r
    })
    return base
  }, [exec.data, ordem, rel])

  const grupos = useMemo(() => {
    if (!grupo) return null
    const m = new Map<string, Linha[]>()
    for (const l of linhas) { const k = String(l[grupo] ?? '—'); m.set(k, [...(m.get(k) ?? []), l]) }
    return [...m.entries()]
  }, [linhas, grupo])

  const totais = rel.colunas.filter((c) => c.totalizar)
  const soma = (ls: Linha[], c: Coluna) => ls.reduce((s, l) => s + Number(l[c.chave] ?? 0), 0)
  const opcoes = (lista: { id: string; nome: string }[] | undefined, vazio: string) => [{ valor: '', rotulo: vazio }, ...(lista ?? []).map((x) => ({ valor: x.id, rotulo: x.nome }))]

  function exportarCsv() {
    const csv = csvDe(rel.colunas, linhas)
    const url = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }))
    const a = document.createElement('a'); a.href = url; a.download = `${rel.id}-${(filtros.mes ?? hojeISO()).slice(0, 7)}.csv`; a.click(); URL.revokeObjectURL(url)
  }
  function salvarFavorito() {
    const nome = nomeFav.trim() || `${rel.titulo} · ${filtros.mes ? formatarMes(filtros.mes) : hojeISO()}`
    salvar.mutate({ relatorio: rel.id, nome, filtros }, { onSuccess: () => setNomeFav('') })
  }

  const linhaTabela = (l: Linha, k: string) => (
    <tr key={k} className={`border-b border-line last:border-0 ${l.destaque ? 'font-semibold bg-surface' : ''}`}>
      {rel.colunas.map((c) => <td key={c.chave} className={`px-3 py-2 ${c.tipo === 'moeda' || c.tipo === 'numero' ? 'text-right tabular-nums' : ''}`}>{formatar(l[c.chave], c)}</td>)}
    </tr>
  )
  const linhaTotal = (ls: Linha[], rotulo: string, k: string) => (
    <tr key={k} className="border-t border-line bg-surface font-semibold">
      {rel.colunas.map((c, i) => <td key={c.chave} className={`px-3 py-2 ${c.tipo === 'moeda' ? 'text-right tabular-nums' : ''}`}>{i === 0 ? rotulo : c.totalizar ? formatarMoeda(soma(ls, c)) : ''}</td>)}
    </tr>
  )

  return (
    <>
      <div className="print:hidden">
        <CabecalhoPagina titulo={rel.titulo} descricao={rel.descricao} acoes={<Link to="/relatorios" className="text-sm text-brand-700 hover:underline">Todos os relatórios</Link>} />
        <Cartao className="mb-4">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {rel.filtros.includes('mes') && <Campo rotulo="Mês" type="month" value={(filtros.mes ?? '').slice(0, 7)} onChange={(e) => def('mes', e.target.value ? `${e.target.value}-01` : '')} />}
            {rel.filtros.includes('periodo') && <>
              <Campo rotulo="De" type="date" value={filtros.de ?? ''} onChange={(e) => def('de', e.target.value)} />
              <Campo rotulo="Até" type="date" value={filtros.ate ?? ''} onChange={(e) => def('ate', e.target.value)} />
            </>}
            {rel.filtros.includes('negocio') && <Selecao rotulo="Negócio" opcoes={[{ valor: '', rotulo: 'Todos' }, { valor: 'pessoal', rotulo: 'Pessoal' }, ...(negocios.data ?? []).map((n) => ({ valor: n.id, rotulo: n.nome }))]} value={filtros.negocio ?? ''} onChange={(e) => def('negocio', e.target.value)} />}
            {rel.filtros.includes('centro') && <Selecao rotulo="Centro de custo" opcoes={[{ valor: '', rotulo: 'Todos' }, { valor: 'geral', rotulo: 'Geral (sem centro)' }, ...(centros.data ?? []).filter((c) => !filtros.negocio || filtros.negocio === 'pessoal' ? true : c.negocio_id === filtros.negocio).map((c) => ({ valor: c.id, rotulo: c.nome }))]} value={filtros.centro ?? ''} onChange={(e) => def('centro', e.target.value)} />}
            {rel.filtros.includes('tipo') && <Selecao rotulo="Tipo" opcoes={[{ valor: '', rotulo: 'Receitas e despesas' }, { valor: 'receita', rotulo: 'Receitas' }, { valor: 'despesa', rotulo: 'Despesas' }]} value={filtros.tipo ?? ''} onChange={(e) => def('tipo', e.target.value)} />}
            {rel.filtros.includes('status') && <Selecao rotulo="Status" opcoes={[{ valor: '', rotulo: 'Previstos e efetivados' }, { valor: 'previsto', rotulo: 'Previstos' }, { valor: 'efetivado', rotulo: 'Efetivados' }, { valor: 'cancelado', rotulo: 'Cancelados' }]} value={filtros.status ?? ''} onChange={(e) => def('status', e.target.value)} />}
            {rel.filtros.includes('pessoa') && <Selecao rotulo="Pessoa" opcoes={opcoes(pessoas.data, 'Todas')} value={filtros.pessoa ?? ''} onChange={(e) => def('pessoa', e.target.value)} />}
            {rel.filtros.includes('categoria') && <Selecao rotulo="Categoria" opcoes={opcoes(categorias.data, 'Todas')} value={filtros.categoria ?? ''} onChange={(e) => def('categoria', e.target.value)} />}
            {rel.filtros.includes('conta') && <Selecao rotulo="Conta" opcoes={opcoes(contas.data, 'Todas')} value={filtros.conta ?? ''} onChange={(e) => def('conta', e.target.value)} />}
            {rel.agrupavel && <Selecao rotulo="Agrupar por" opcoes={[{ valor: '', rotulo: 'Sem agrupamento' }, ...rel.agrupavel.map((k) => ({ valor: k, rotulo: rel.colunas.find((c) => c.chave === k)?.rotulo ?? k }))]} value={grupo} onChange={(e) => setGrupo(e.target.value)} />}
          </div>
          <div className="mt-4 flex flex-wrap items-end gap-2">
            <Botao onClick={() => setGerado(true)} carregando={exec.isFetching}>Gerar</Botao>
            <Botao variante="secundario" onClick={exportarCsv} disabled={!exec.data?.length}>Exportar CSV</Botao>
            <Botao variante="secundario" onClick={() => window.print()} disabled={!exec.data?.length}>Imprimir / PDF</Botao>
            <span className="ml-auto flex items-end gap-2">
              <Campo rotulo="Salvar como favorito" placeholder="nome (opcional)" value={nomeFav} onChange={(e) => setNomeFav(e.target.value)} className="h-10" />
              <Botao variante="secundario" onClick={salvarFavorito} carregando={salvar.isPending}>Salvar</Botao>
            </span>
          </div>
          {salvar.error != null && <div className="mt-3"><Alerta tipo="erro">{mensagemDeErro(salvar.error)}</Alerta></div>}
        </Cartao>
      </div>

      <div className="hidden print:block mb-4">
        <h1 className="text-xl font-semibold">{rel.titulo}</h1>
        <p className="text-sm">{filtros.mes && rel.filtros.includes('mes') ? formatarMes(filtros.mes) : rel.filtros.includes('periodo') ? `${formatarData(filtros.de ?? '')} a ${formatarData(filtros.ate ?? '')}` : `em ${formatarData(hojeISO())}`} · gerado em {new Date().toLocaleString('pt-BR')}</p>
      </div>

      {!gerado && <p className="text-sm text-ink-muted">Ajuste os filtros e clique em <strong>Gerar</strong>.</p>}
      {gerado && exec.isPending && <Carregando texto="Gerando…" />}
      {exec.error != null && <Alerta tipo="erro">{mensagemDeErro(exec.error)}</Alerta>}
      {gerado && exec.isSuccess && (
        <Cartao className="p-0">
          {linhas.length === 0 ? <p className="px-6 py-8 text-center text-sm text-ink-muted">Nada encontrado com esses filtros.</p> : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                  <tr className="border-b border-line">
                    {rel.colunas.map((c) => (
                      <th key={c.chave} className={`px-3 py-2 font-medium ${c.tipo === 'moeda' || c.tipo === 'numero' ? 'text-right' : ''}`}>
                        <button type="button" className="hover:text-ink" onClick={() => setOrdem((o) => ({ chave: c.chave, desc: o?.chave === c.chave ? !o.desc : false }))}>
                          {c.rotulo}{ordem?.chave === c.chave ? (ordem.desc ? ' ↓' : ' ↑') : ''}
                        </button>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {grupos ? grupos.flatMap(([nome, ls]) => [
                    <tr key={`g-${nome}`} className="bg-brand-50"><td colSpan={rel.colunas.length} className="px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-brand-900">{ROTULOS[nome] ?? nome} · {ls.length}</td></tr>,
                    ...ls.map((l, i) => linhaTabela(l, `${nome}-${i}`)),
                    ...(totais.length > 0 ? [linhaTotal(ls, `Subtotal ${ROTULOS[nome] ?? nome}`, `t-${nome}`)] : []),
                  ]) : linhas.map((l, i) => linhaTabela(l, String(i)))}
                  {totais.length > 0 && linhaTotal(linhas, `Total (${linhas.length})`, 'total')}
                </tbody>
              </table>
            </div>
          )}
          {linhas.length >= 5000 && <p className="px-6 py-3 text-xs text-amber-700">Mostrando as primeiras 5.000 linhas — refine o período.</p>}
        </Cartao>
      )}
    </>
  )
}
