import { useMemo, useRef, useState, type FormEvent } from 'react'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../../core/formatos'
import { useEstoqueItens, useEstoqueCategorias } from '../../estoque/api'
import { useEntregarPremioPontos, usePontosPremiosAdmin, usePontosResgatesAdmin, useSalvarPontoPremio } from '../api'
import type { PontoPremioAdmin } from '../tipos'

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

function FormPremio({ negocioId, premio, aoConcluir }: { negocioId: string; premio?: PontoPremioAdmin; aoConcluir: () => void }) {
  const salvar = useSalvarPontoPremio()
  const itens = useEstoqueItens(); const categorias = useEstoqueCategorias()
  const [nome, setNome] = useState(premio?.nome ?? '')
  const [itemId, setItemId] = useState(premio?.item_id ?? '')
  const [valor, setValor] = useState(premio?.valor_reais == null ? '' : String(premio.valor_reais))
  const [foto, setFoto] = useState<string | null>(premio?.foto ?? null)
  const [ativo, setAtivo] = useState(premio?.ativo ?? true)
  const [erro, setErro] = useState<string | null>(null)
  const arquivoRef = useRef<HTMLInputElement>(null)
  const catBrindes = useMemo(() => new Set((categorias.data ?? []).filter((c) => c.negocio_id === negocioId && c.nome.toLowerCase().startsWith('brinde')).map((c) => c.id)), [categorias.data, negocioId])
  const brindes = (itens.data ?? []).filter((i) => i.negocio_id === negocioId && i.ativo && catBrindes.has(i.categoria_id))
  const valorNum = Number(valor.replace(',', '.'))
  const pontosCusto = valorNum > 0 ? Math.ceil(valorNum / 0.22) : 0
  async function aoEscolherFoto(arquivo: File | undefined) {
    if (!arquivo) return
    try { setFoto(await comprimirFoto(arquivo)); setErro(null) } catch (e) { setErro(e instanceof Error ? e.message : 'Falha ao ler a foto.') }
  }
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (nome.trim().length < 2) { setErro('Dê um nome ao prêmio.'); return }
    if (!itemId) { setErro('Vincule o prêmio a um item da categoria Brindes do Estoque.'); return }
    if (!(valorNum > 0)) { setErro('Informe o preço do prêmio em R$.'); return }
    setErro(null)
    salvar.mutate({ id: premio?.id, dados: { negocio_id: negocioId, nome: nome.trim(), foto, item_id: itemId, valor_reais: valorNum, ativo } }, { onSuccess: aoConcluir })
  }
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || salvar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(salvar.error)}</Alerta>}
      {brindes.length === 0 && <Alerta tipo="info">Cadastre os itens dos prêmios na categoria <b>Brindes</b> do Estoque antes (é de lá que sai o saldo e o custo real de entrega).</Alerta>}
      <div className="flex items-start gap-4">
        <button type="button" onClick={() => arquivoRef.current?.click()} className="shrink-0 overflow-hidden rounded-lg border border-line hover:border-brand-600/60" title="Enviar foto">
          {foto ? <img src={foto} alt="Foto do prêmio" className="size-28 object-cover" /> : <span className="flex size-28 flex-col items-center justify-center gap-1 text-xs text-ink-muted"><span className="text-3xl">📷</span>Enviar foto</span>}
        </button>
        <input ref={arquivoRef} type="file" accept="image/*" className="hidden" onChange={(e) => void aoEscolherFoto(e.target.files?.[0])} />
        <div className="grid flex-1 gap-4">
          <Campo rotulo="Nome do prêmio (como o cliente vê)" value={nome} onChange={(e) => setNome(e.target.value)} maxLength={80} autoFocus />
          <Campo rotulo="Preço do prêmio (R$)" inputMode="decimal" value={valor} onChange={(e) => setValor(e.target.value)} placeholder="ex.: 22,00" />
        </div>
      </div>
      <Selecao rotulo="Item do Estoque (categoria Brindes)" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...brindes.map((i) => ({ valor: i.id, rotulo: `${i.nome} · saldo ${i.quantidade_atual}` }))]} value={itemId} onChange={(e) => setItemId(e.target.value)} />
      {valorNum > 0 && <p className="text-xs text-ink-muted">Custa <b>{pontosCusto} pontos</b> (R$ {valor} ÷ R$ 0,22/ponto, arredondado pra cima).</p>}
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />Prêmio ativo na vitrine</label>
      <div className="flex justify-end"><Botao type="submit" carregando={salvar.isPending}>{premio ? 'Salvar' : 'Adicionar prêmio'}</Botao></div>
    </form>
  )
}

/** Admin: catálogo de prêmios do programa de pontos + resgates aguardando entrega. */
export function VitrinePontosAdmin({ negocioId }: { negocioId: string }) {
  const premiosQ = usePontosPremiosAdmin(); const itens = useEstoqueItens()
  const resgatesQ = usePontosResgatesAdmin(); const entregar = useEntregarPremioPontos()
  const [janela, setJanela] = useState<{ tipo: 'premio'; premio?: PontoPremioAdmin } | null>(null)
  const premios = (premiosQ.data ?? []).filter((p) => p.negocio_id === negocioId)
  const pendentes = (resgatesQ.data ?? []).filter((r) => r.negocio_id === negocioId && r.tipo === 'Prêmio físico' && r.situacao === 'Aguardando entrega')
  const saldoItem = useMemo(() => new Map((itens.data ?? []).map((i) => [i.id, Number(i.quantidade_atual)])), [itens.data])
  return (
    <div className="space-y-4">
      <Cartao className="p-0">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-6 py-3">
          <div>
            <h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Catálogo de prêmios (pontos)</h2>
            <p className="text-xs text-ink-muted">Preço em R$ vira custo em pontos sozinho (R$ 0,22/ponto). O cliente escolhe pelo Portal em "Meus pontos".</p>
          </div>
          <Botao onClick={() => setJanela({ tipo: 'premio' })}>Novo prêmio</Botao>
        </div>
        <div className="px-6 py-4">
          {premios.length === 0 ? <p className="text-xs text-ink-muted">Nenhum prêmio cadastrado ainda.</p> : (
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-4">
              {premios.map((p) => {
                const saldo = saldoItem.get(p.item_id) ?? 0
                return (
                  <button key={p.id} type="button" onClick={() => setJanela({ tipo: 'premio', premio: p })} className="overflow-hidden rounded-lg border border-line text-left hover:border-brand-600/60">
                    {p.foto ? <img src={p.foto} alt={p.nome} className="aspect-square w-full object-cover" /> : <div className="flex aspect-square w-full items-center justify-center bg-surface text-4xl">🎁</div>}
                    <div className="px-2 py-2">
                      <p className="truncate text-sm font-medium">{p.nome}</p>
                      <p className="text-xs text-ink-muted">{formatarMoeda(p.valor_reais)} · {p.pontos_custo} pts · saldo {saldo}</p>
                      {(!p.ativo || saldo < 1) && <Distintivo tom={!p.ativo ? 'neutro' : 'alerta'}>{!p.ativo ? 'Inativo' : 'Sem saldo'}</Distintivo>}
                    </div>
                  </button>
                )
              })}
            </div>
          )}
        </div>
      </Cartao>
      <Cartao className="p-0">
        <div className="border-b border-line px-6 py-3"><h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Resgates aguardando entrega ({pendentes.length})</h2></div>
        {entregar.error != null && <div className="px-6 pt-3"><Alerta tipo="erro">{mensagemDeErro(entregar.error)}</Alerta></div>}
        {pendentes.length === 0 ? <p className="px-6 py-6 text-sm text-ink-muted">Nada pendente.</p> : (
          <ul className="divide-y divide-line">
            {pendentes.map((r) => (
              <li key={r.id} className="flex items-center justify-between px-6 py-3 text-sm">
                <span>🎁 <b>{r.premio}</b> — {r.cliente} <span className="text-xs text-ink-muted">· resgatado em {formatarData(r.criado_em.slice(0, 10))}</span></span>
                <Botao variante="secundario" carregando={entregar.isPending} onClick={() => entregar.mutate({ id: r.id })}>Entregue</Botao>
              </li>
            ))}
          </ul>
        )}
      </Cartao>
      <Modal aberto={janela !== null} aoFechar={() => setJanela(null)} titulo={janela?.premio ? 'Editar prêmio' : 'Novo prêmio'}>
        {janela?.tipo === 'premio' && <FormPremio negocioId={negocioId} premio={janela.premio} aoConcluir={() => setJanela(null)} />}
      </Modal>
    </div>
  )
}
