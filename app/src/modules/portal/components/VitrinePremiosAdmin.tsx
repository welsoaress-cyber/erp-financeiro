import { useMemo, useRef, useState, type FormEvent } from 'react'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarMoeda } from '../../../core/formatos'
import { useEstoqueItens, useEstoqueCategorias } from '../../estoque/api'
import { useCriarPremiosLote, useFaixasAdmin, usePremiosAdmin, useSalvarFaixa, useSalvarPremio } from '../api'
import type { IndicacaoFaixa, IndicacaoPremio } from '../tipos'

/** Comprime a foto no navegador (canvas → JPEG ~600px) e devolve um data URL. */
async function comprimirFoto(arquivo: File): Promise<string> {
  const bitmap = await createImageBitmap(arquivo)
  const escala = Math.min(1, 600 / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(bitmap.width * escala)
  canvas.height = Math.round(bitmap.height * escala)
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  bitmap.close()
  const dataUrl = canvas.toDataURL('image/jpeg', 0.75)
  if (dataUrl.length > 400_000) throw new Error('Foto muito grande mesmo comprimida — use uma imagem menor.')
  return dataUrl
}

function FormFaixa({ negocioId, faixa, aoConcluir }: { negocioId: string; faixa?: IndicacaoFaixa; aoConcluir: () => void }) {
  const salvar = useSalvarFaixa()
  const [num, setNum] = useState(String(faixa?.faixa ?? ''))
  const [nome, setNome] = useState(faixa?.nome ?? '')
  const [planoAte, setPlanoAte] = useState(faixa?.plano_ate == null ? '' : String(faixa.plano_ate))
  const [teto, setTeto] = useState(faixa?.teto == null ? '' : String(faixa.teto))
  const [ativo, setAtivo] = useState(faixa?.ativo ?? true)
  const [erro, setErro] = useState<string | null>(null)
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const f = Number(num), t = Number(teto.replace(',', '.')), p = planoAte.trim() === '' ? null : Number(planoAte.replace(',', '.'))
    if (!Number.isInteger(f) || f < 1 || f > 9) { setErro('Número da faixa: 1 a 9.'); return }
    if (nome.trim().length < 2) { setErro('Dê um nome à faixa (ex.: 200 Mb).'); return }
    if (!(t > 0)) { setErro('Informe o teto do prêmio (R$).'); return }
    if (p !== null && !(p > 0)) { setErro('Plano até: valor em R$ ou vazio (pega tudo acima).'); return }
    setErro(null)
    salvar.mutate({ id: faixa?.id, dados: { negocio_id: negocioId, faixa: f, nome: nome.trim(), plano_ate: p, teto: t, ativo } }, { onSuccess: aoConcluir })
  }
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || salvar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(salvar.error)}</Alerta>}
      <div className="grid grid-cols-2 gap-4">
        <Campo rotulo="Nº da faixa" type="number" min={1} max={9} value={num} onChange={(e) => setNum(e.target.value)} disabled={Boolean(faixa)} />
        <Campo rotulo="Nome (plano)" value={nome} onChange={(e) => setNome(e.target.value)} placeholder="200 Mb — R$ 80/mês" maxLength={60} />
        <Campo rotulo="Mensalidade do indicado até (R$)" inputMode="decimal" value={planoAte} onChange={(e) => setPlanoAte(e.target.value)} placeholder="vazio = tudo acima" />
        <Campo rotulo="Teto do prêmio (R$)" inputMode="decimal" value={teto} onChange={(e) => setTeto(e.target.value)} />
      </div>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />Faixa ativa</label>
      <div className="flex justify-end"><Botao type="submit" carregando={salvar.isPending}>{faixa ? 'Salvar' : 'Criar faixa'}</Botao></div>
    </form>
  )
}

function FormPremio({ negocioId, premio, faixas, aoConcluir }: { negocioId: string; premio?: IndicacaoPremio; faixas: IndicacaoFaixa[]; aoConcluir: () => void }) {
  const salvar = useSalvarPremio()
  const itens = useEstoqueItens(); const categorias = useEstoqueCategorias()
  const [nome, setNome] = useState(premio?.nome ?? '')
  const [faixa, setFaixa] = useState(String(premio?.faixa ?? faixas[0]?.faixa ?? 1))
  const [itemId, setItemId] = useState(premio?.item_id ?? '')
  const [foto, setFoto] = useState<string | null>(premio?.foto ?? null)
  const [ativo, setAtivo] = useState(premio?.ativo ?? true)
  const [erro, setErro] = useState<string | null>(null)
  const arquivoRef = useRef<HTMLInputElement>(null)
  const catBrindes = useMemo(() => new Set((categorias.data ?? []).filter((c) => c.negocio_id === negocioId && c.nome.toLowerCase().startsWith('brinde')).map((c) => c.id)), [categorias.data, negocioId])
  const brindes = (itens.data ?? []).filter((i) => i.negocio_id === negocioId && i.ativo && catBrindes.has(i.categoria_id))
  const item = brindes.find((i) => i.id === itemId)
  const faixaSel = faixas.find((f) => String(f.faixa) === faixa)
  async function aoEscolherFoto(arquivo: File | undefined) {
    if (!arquivo) return
    try { setFoto(await comprimirFoto(arquivo)); setErro(null) } catch (e) { setErro(e instanceof Error ? e.message : 'Falha ao ler a foto.') }
  }
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (nome.trim().length < 2) { setErro('Dê um nome ao prêmio.'); return }
    if (!itemId) { setErro('Vincule o prêmio a um item da categoria Brindes do Estoque.'); return }
    setErro(null)
    salvar.mutate({ id: premio?.id, dados: { negocio_id: negocioId, nome: nome.trim(), foto, faixa: Number(faixa), item_id: itemId, ativo } }, { onSuccess: aoConcluir })
  }
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || salvar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(salvar.error)}</Alerta>}
      {brindes.length === 0 && <Alerta tipo="info">Cadastre os itens dos prêmios na categoria <b>Brindes</b> do Estoque antes (é de lá que sai o saldo e o custo).</Alerta>}
      <div className="flex items-start gap-4">
        <button type="button" onClick={() => arquivoRef.current?.click()} className="shrink-0 overflow-hidden rounded-lg border border-line hover:border-brand-600/60" title="Enviar foto">
          {foto ? <img src={foto} alt="Foto do prêmio" className="size-28 object-cover" /> : <span className="flex size-28 flex-col items-center justify-center gap-1 text-xs text-ink-muted"><span className="text-3xl">📷</span>Enviar foto</span>}
        </button>
        <input ref={arquivoRef} type="file" accept="image/*" className="hidden" onChange={(e) => void aoEscolherFoto(e.target.files?.[0])} />
        <div className="grid flex-1 gap-4">
          <Campo rotulo="Nome do prêmio (como o cliente vê)" value={nome} onChange={(e) => setNome(e.target.value)} maxLength={80} autoFocus />
          <Selecao rotulo="Faixa" opcoes={faixas.map((f) => ({ valor: String(f.faixa), rotulo: `${f.faixa} · ${f.nome} (até ${formatarMoeda(f.teto)})` }))} value={faixa} onChange={(e) => setFaixa(e.target.value)} />
        </div>
      </div>
      <Selecao rotulo="Item do Estoque (categoria Brindes)" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...brindes.map((i) => ({ valor: i.id, rotulo: `${i.nome} · saldo ${i.quantidade_atual} · custo ${formatarMoeda(i.valor_custo ?? 0)}` }))]} value={itemId} onChange={(e) => setItemId(e.target.value)} />
      {item && faixaSel && (item.valor_custo ?? 0) > faixaSel.teto && <Alerta tipo="info">Atenção: o custo do item ({formatarMoeda(item.valor_custo ?? 0)}) passa o teto da faixa ({formatarMoeda(faixaSel.teto)}).</Alerta>}
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />Prêmio ativo na vitrine</label>
      <div className="flex justify-end"><Botao type="submit" carregando={salvar.isPending}>{premio ? 'Salvar' : 'Adicionar prêmio'}</Botao></div>
    </form>
  )
}

/** Nome inicial a partir do arquivo: "uno-no-mercy.jpg" → "Uno No Mercy". */
function nomeDoArquivo(arquivo: File): string {
  const base = arquivo.name.replace(/\.[^.]+$/, '').replace(/[-_.]+/g, ' ').replace(/\s+/g, ' ').trim()
  return base.replace(/\b\w/g, (c) => c.toUpperCase()).slice(0, 80) || 'Prêmio'
}

function FormLote({ negocioId, faixas, aoConcluir }: { negocioId: string; faixas: IndicacaoFaixa[]; aoConcluir: () => void }) {
  const criar = useCriarPremiosLote()
  const [faixa, setFaixa] = useState(String(faixas[0]?.faixa ?? 1))
  const [linhas, setLinhas] = useState<{ nome: string; foto: string }[]>([])
  const [erro, setErro] = useState<string | null>(null)
  const arquivoRef = useRef<HTMLInputElement>(null)
  async function aoEscolherFotos(arquivos: FileList | null) {
    if (!arquivos?.length) return
    setErro(null)
    const novas: { nome: string; foto: string }[] = []
    for (const a of Array.from(arquivos)) {
      try { novas.push({ nome: nomeDoArquivo(a), foto: await comprimirFoto(a) }) }
      catch { setErro(`Não consegui ler "${a.name}" — pulei essa.`) }
    }
    setLinhas((l) => [...l, ...novas])
  }
  return (
    <div className="space-y-4">
      {(erro || criar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(criar.error)}</Alerta>}
      <p className="text-sm text-ink-muted">Escolha a faixa e selecione as fotos de uma vez — cada foto vira um prêmio, com o item criado automaticamente na categoria <b>Brindes</b> do Estoque (saldo 0: dê entrada quando comprar; sem saldo o prêmio ainda não aparece na vitrine). Ajuste os nomes antes de criar.</p>
      <div className="flex flex-wrap items-end gap-3">
        <Selecao rotulo="Faixa" opcoes={faixas.map((f) => ({ valor: String(f.faixa), rotulo: `${f.faixa} · ${f.nome} (até ${formatarMoeda(f.teto)})` }))} value={faixa} onChange={(e) => setFaixa(e.target.value)} />
        <Botao variante="secundario" onClick={() => arquivoRef.current?.click()}>Selecionar fotos…</Botao>
        <input ref={arquivoRef} type="file" accept="image/*" multiple className="hidden" onChange={(e) => { void aoEscolherFotos(e.target.files); e.target.value = '' }} />
      </div>
      {linhas.length > 0 && (
        <ul className="max-h-80 divide-y divide-line overflow-y-auto rounded-md border border-line">
          {linhas.map((l, i) => (
            <li key={i} className="flex items-center gap-3 px-3 py-2">
              <img src={l.foto} alt={l.nome} className="size-12 shrink-0 rounded-md border border-line object-cover" />
              <input value={l.nome} onChange={(e) => setLinhas((ls) => ls.map((x, j) => (j === i ? { ...x, nome: e.target.value } : x)))} className="h-9 w-full rounded-md border border-line bg-white px-2 text-sm" aria-label={`Nome do prêmio ${i + 1}`} />
              <button type="button" className="text-xs text-ink-muted hover:underline" onClick={() => setLinhas((ls) => ls.filter((_, j) => j !== i))}>remover</button>
            </li>
          ))}
        </ul>
      )}
      <div className="flex justify-end">
        <Botao carregando={criar.isPending} disabled={linhas.length === 0 || linhas.some((l) => l.nome.trim().length < 2)}
          onClick={() => criar.mutate({ negocioId, faixa: Number(faixa), premios: linhas.map((l) => ({ nome: l.nome.trim(), foto: l.foto })) }, { onSuccess: aoConcluir })}>
          Criar {linhas.length} prêmio(s) na {faixa}ª faixa
        </Botao>
      </div>
    </div>
  )
}

/** Cartão do admin: faixas configuráveis + cadastro de prêmios da vitrine. */
export function VitrinePremiosAdmin({ negocioId, negocioSlug }: { negocioId: string; negocioSlug: string }) {
  const faixasQ = useFaixasAdmin(); const premiosQ = usePremiosAdmin(); const itens = useEstoqueItens()
  const [janela, setJanela] = useState<{ tipo: 'faixa'; faixa?: IndicacaoFaixa } | { tipo: 'premio'; premio?: IndicacaoPremio } | { tipo: 'lote' } | null>(null)
  const faixas = (faixasQ.data ?? []).filter((f) => f.negocio_id === negocioId)
  const premios = (premiosQ.data ?? []).filter((p) => p.negocio_id === negocioId)
  const saldoItem = useMemo(() => new Map((itens.data ?? []).map((i) => [i.id, Number(i.quantidade_atual)])), [itens.data])
  const linkPublico = `${window.location.origin}/portal/premios/${negocioSlug}`
  const [copiado, setCopiado] = useState(false)
  async function copiar() { try { await navigator.clipboard.writeText(linkPublico); setCopiado(true); setTimeout(() => setCopiado(false), 2000) } catch { /* sem clipboard */ } }
  return (
    <Cartao className="p-0">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-6 py-3">
        <div>
          <h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Vitrine de prêmios (Indique e Ganhe)</h2>
          <p className="text-xs text-ink-muted">O cliente escolhe o presente pela vitrine do portal, na faixa do plano do indicado. Sem saldo em estoque, o prêmio some sozinho.</p>
        </div>
        <span className="flex gap-2">
          <Botao variante="secundario" onClick={copiar}>{copiado ? 'Link copiado!' : 'Copiar link público'}</Botao>
          <Botao variante="secundario" onClick={() => setJanela({ tipo: 'faixa' })}>Nova faixa</Botao>
          <Botao variante="secundario" onClick={() => setJanela({ tipo: 'premio' })} disabled={faixas.length === 0}>Novo prêmio</Botao>
          <Botao onClick={() => setJanela({ tipo: 'lote' })} disabled={faixas.length === 0}>Adicionar em lote</Botao>
        </span>
      </div>
      <div className="grid gap-4 px-6 py-4 lg:grid-cols-[280px_1fr]">
        <div>
          <h3 className="mb-2 text-xs font-semibold uppercase text-ink-muted">Faixas por plano do indicado</h3>
          {faixas.length === 0 ? <p className="text-xs text-ink-muted">Nenhuma faixa — vale a régua padrão (até R$ 60 → R$ 30 · até R$ 80 → R$ 50 · acima → R$ 80). Cadastre para personalizar.</p> : (
            <ul className="divide-y divide-line rounded-md border border-line text-sm">
              {faixas.map((f) => (
                <li key={f.id}>
                  <button type="button" className="flex w-full items-center justify-between px-3 py-2 text-left hover:bg-surface" onClick={() => setJanela({ tipo: 'faixa', faixa: f })}>
                    <span><span className="font-medium">{f.faixa}ª · {f.nome}</span><span className="block text-xs text-ink-muted">plano {f.plano_ate == null ? 'acima das demais' : `até ${formatarMoeda(f.plano_ate)}`} · prêmio até {formatarMoeda(f.teto)}</span></span>
                    {!f.ativo && <Distintivo tom="neutro">Inativa</Distintivo>}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
        <div>
          <h3 className="mb-2 text-xs font-semibold uppercase text-ink-muted">Prêmios ({premios.length})</h3>
          {premios.length === 0 ? <p className="text-xs text-ink-muted">Nenhum prêmio cadastrado — a vitrine usa os itens da categoria Brindes por custo (regra antiga). Cadastre prêmios com foto para a vitrine visual.</p> : (
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-4">
              {premios.map((p) => {
                const saldo = saldoItem.get(p.item_id) ?? 0
                return (
                  <button key={p.id} type="button" onClick={() => setJanela({ tipo: 'premio', premio: p })} className="overflow-hidden rounded-lg border border-line text-left hover:border-brand-600/60">
                    {p.foto ? <img src={p.foto} alt={p.nome} className="aspect-square w-full object-cover" /> : <div className="flex aspect-square w-full items-center justify-center bg-surface text-4xl">🎁</div>}
                    <div className="px-2 py-2">
                      <p className="truncate text-sm font-medium">{p.nome}</p>
                      <p className="text-xs text-ink-muted">{p.faixa}ª faixa · saldo {saldo}</p>
                      {(!p.ativo || saldo < 1) && <Distintivo tom={saldo < 1 ? 'alerta' : 'neutro'}>{saldo < 1 ? 'Sem saldo — fora da vitrine' : 'Inativo'}</Distintivo>}
                    </div>
                  </button>
                )
              })}
            </div>
          )}
        </div>
      </div>
      <Modal aberto={janela !== null} aoFechar={() => setJanela(null)} titulo={janela?.tipo === 'faixa' ? (janela.faixa ? `Editar ${janela.faixa.faixa}ª faixa` : 'Nova faixa') : janela?.tipo === 'premio' ? (janela.premio ? 'Editar prêmio' : 'Novo prêmio') : janela?.tipo === 'lote' ? 'Adicionar prêmios em lote' : ''}>
        {janela?.tipo === 'faixa' && <FormFaixa negocioId={negocioId} faixa={janela.faixa} aoConcluir={() => setJanela(null)} />}
        {janela?.tipo === 'premio' && <FormPremio negocioId={negocioId} premio={janela.premio} faixas={faixas.filter((f) => f.ativo)} aoConcluir={() => setJanela(null)} />}
        {janela?.tipo === 'lote' && <FormLote negocioId={negocioId} faixas={faixas.filter((f) => f.ativo)} aoConcluir={() => setJanela(null)} />}
      </Modal>
    </Cartao>
  )
}
