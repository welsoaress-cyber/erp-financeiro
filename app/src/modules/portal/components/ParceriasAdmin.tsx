import { useRef, useState, type ChangeEvent, type FormEvent } from 'react'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { decodificar, lerCsv, type Tabela } from '../../configuracoes/importacao/csv'
import { lerXlsx } from '../../configuracoes/importacao/xlsx'
import { useAlternarAtivoParceria, useImportarParceriasLeveduca, useParceriasAdmin, useSalvarFotosParceria, useSalvarParceria } from '../api'
import type { LinhaParceriaLeveduca, ParceriaAdmin } from '../tipos'

const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim()
const COLUNAS_LEVEDUCA: { chave: keyof LinhaParceriaLeveduca; pistas: string[] }[] = [
  { chave: 'nome', pistas: ['nome do parceiro', 'parceiro', 'nome'] },
  { chave: 'tipo', pistas: ['tipo de parceria', 'tipo'] },
  { chave: 'beneficio', pistas: ['beneficio'] },
  { chave: 'categoria', pistas: ['categorias', 'categoria'] },
  { chave: 'cobertura', pistas: ['cobertura'] },
  { chave: 'status', pistas: ['status'] },
]

function tabelaParaLinhas(t: Tabela): LinhaParceriaLeveduca[] {
  const cols = t.cabecalho.map(normalizar)
  const idx = (pistas: string[]) => cols.findIndex((c) => pistas.some((p) => c.includes(p)))
  const indices = Object.fromEntries(COLUNAS_LEVEDUCA.map((c) => [c.chave, idx(c.pistas)])) as Record<keyof LinhaParceriaLeveduca, number>
  if (indices.nome < 0 || indices.beneficio < 0) throw new Error('Não achei as colunas "Nome do Parceiro" e "Benefício" na planilha — confira o cabeçalho.')
  const pega = (l: string[], i: number) => (i < 0 ? '' : (l[i] ?? '').trim())
  return t.linhas
    .map((l) => ({ nome: pega(l, indices.nome), tipo: pega(l, indices.tipo), beneficio: pega(l, indices.beneficio), categoria: pega(l, indices.categoria), cobertura: pega(l, indices.cobertura), status: pega(l, indices.status) || 'Ativo' }))
    .filter((l) => l.nome && l.beneficio)
}

function ImportarLeveduca({ negocioId }: { negocioId: string }) {
  const importar = useImportarParceriasLeveduca()
  const [linhas, setLinhas] = useState<LinhaParceriaLeveduca[] | null>(null)
  const [nomeArquivo, setNomeArquivo] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [importados, setImportados] = useState<number | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  async function aoEscolher(e: ChangeEvent<HTMLInputElement>) {
    const arquivo = e.target.files?.[0]
    if (!arquivo) return
    setErro(null); setImportados(null); setNomeArquivo(arquivo.name)
    try {
      const buffer = await arquivo.arrayBuffer()
      const tabela = /\.(xlsx|xls)$/i.test(arquivo.name) ? await lerXlsx(buffer) : lerCsv(decodificar(buffer))
      const l = tabelaParaLinhas(tabela)
      if (l.length === 0) throw new Error('Nenhuma linha válida (precisa de nome e benefício preenchidos).')
      setLinhas(l)
    } catch (e2) { setErro(e2 instanceof Error ? e2.message : 'Falha ao ler o arquivo.'); setLinhas(null) }
  }
  function confirmar() {
    if (!linhas) return
    importar.mutate({ negocioId, linhas }, { onSuccess: (n) => { setImportados(n); setLinhas(null); setNomeArquivo(''); if (inputRef.current) inputRef.current.value = '' } })
  }
  return (
    <Cartao>
      <h2 className="mb-1 text-sm font-semibold uppercase tracking-wide text-ink-muted">Importar lista da Leveduca</h2>
      <p className="mb-3 text-sm text-ink-muted">Sobe a planilha (CSV ou XLSX) que a Leveduca manda — <b>substitui toda a lista anterior</b> desse negócio. Colunas esperadas: Nome do Parceiro, Tipo de Parceria, Benefício, Categorias, Cobertura, Status.</p>
      {erro && <div className="mb-3"><Alerta tipo="erro">{erro}</Alerta></div>}
      {importar.error != null && <div className="mb-3"><Alerta tipo="erro">{mensagemDeErro(importar.error)}</Alerta></div>}
      {importados !== null && <div className="mb-3"><Alerta tipo="sucesso">{importados} parceiro(s) importado(s) — lista anterior da Leveduca foi substituída.</Alerta></div>}
      <input ref={inputRef} type="file" accept=".csv,.xlsx,.xls" onChange={(e) => void aoEscolher(e)} className="block text-sm" />
      {linhas && (
        <div className="mt-3 flex items-center gap-3">
          <p className="text-sm">"{nomeArquivo}": <b>{linhas.length}</b> parceiro(s) prontos pra importar.</p>
          <Botao carregando={importar.isPending} onClick={confirmar}>Confirmar importação</Botao>
        </div>
      )}
    </Cartao>
  )
}

function FormParceria({ negocioId, parceria, aoConcluir }: { negocioId: string; parceria?: ParceriaAdmin; aoConcluir: () => void }) {
  const salvar = useSalvarParceria()
  const [nome, setNome] = useState(parceria?.nome ?? '')
  const [tipo, setTipo] = useState(parceria?.tipo ?? 'Online')
  const [beneficio, setBeneficio] = useState(parceria?.beneficio ?? '')
  const [categoria, setCategoria] = useState(parceria?.categoria ?? '')
  const [cobertura, setCobertura] = useState(parceria?.cobertura ?? '')
  const [ativo, setAtivo] = useState(parceria?.ativo ?? true)
  const [erro, setErro] = useState<string | null>(null)
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (nome.trim().length < 2) { setErro('Dê um nome ao parceiro.'); return }
    if (beneficio.trim().length < 2) { setErro('Descreva o benefício.'); return }
    setErro(null)
    salvar.mutate({ id: parceria?.id, dados: { negocio_id: negocioId, nome: nome.trim(), tipo: tipo.trim() || null, beneficio: beneficio.trim(), categoria: categoria.trim() || null, cobertura: cobertura.trim() || null, ativo } }, { onSuccess: aoConcluir })
  }
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || salvar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(salvar.error)}</Alerta>}
      <Campo rotulo="Nome do parceiro" value={nome} onChange={(e) => setNome(e.target.value)} maxLength={120} autoFocus />
      <Campo rotulo="Benefício (o que o cliente ganha)" value={beneficio} onChange={(e) => setBeneficio(e.target.value)} maxLength={300} />
      <div className="grid gap-4 sm:grid-cols-3">
        <Selecao rotulo="Tipo" opcoes={[{ valor: 'Online', rotulo: 'Online' }, { valor: 'Presencial', rotulo: 'Presencial' }]} value={tipo} onChange={(e) => setTipo(e.target.value)} />
        <Campo rotulo="Categoria" value={categoria} onChange={(e) => setCategoria(e.target.value)} placeholder="ex.: Beleza" />
        <Campo rotulo="Cobertura" value={cobertura} onChange={(e) => setCobertura(e.target.value)} placeholder="ex.: Nacional" />
      </div>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />Parceria ativa no Portal</label>
      <div className="flex justify-end"><Botao type="submit" carregando={salvar.isPending}>{parceria ? 'Salvar' : 'Adicionar parceiro'}</Botao></div>
    </form>
  )
}

/** Comprime a foto no navegador (canvas → JPEG ~700px) e devolve um data URL. Mesma lógica da vitrine de pontos. */
async function comprimirFoto(arquivo: File): Promise<string> {
  const bitmap = await createImageBitmap(arquivo)
  const escala = Math.min(1, 700 / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(bitmap.width * escala)
  canvas.height = Math.round(bitmap.height * escala)
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  bitmap.close()
  const dataUrl = canvas.toDataURL('image/jpeg', 0.82)
  if (dataUrl.length > 400_000) throw new Error('Foto muito grande mesmo comprimida — use uma imagem menor.')
  return dataUrl
}

function SlotFoto({ rotulo, valor, aoTrocar, aoRemover, carregando }: { rotulo: string; valor: string | null; aoTrocar: (arquivo: File) => void; aoRemover: () => void; carregando: boolean }) {
  const inputRef = useRef<HTMLInputElement>(null)
  return (
    <div className="space-y-1">
      <p className="text-xs font-medium text-ink-muted">{rotulo}</p>
      <div className="overflow-hidden rounded-lg border border-line">
        {valor ? <img src={valor} alt={rotulo} className="aspect-square w-full object-cover" /> : (
          <button type="button" onClick={() => inputRef.current?.click()} className="flex aspect-square w-full flex-col items-center justify-center gap-1 text-xs text-ink-muted hover:bg-surface" disabled={carregando}>
            <span className="text-2xl">📷</span>Adicionar
          </button>
        )}
      </div>
      <input ref={inputRef} type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) aoTrocar(f); e.target.value = '' }} />
      {valor && (
        <div className="flex gap-2 text-xs">
          <a href={valor} download={`${rotulo}.jpg`} className="text-brand-700 hover:underline">Baixar</a>
          <button type="button" onClick={() => inputRef.current?.click()} className="text-ink-muted hover:underline" disabled={carregando}>Trocar</button>
          <button type="button" onClick={aoRemover} className="text-red-600 hover:underline" disabled={carregando}>Remover</button>
        </div>
      )}
    </div>
  )
}

/** Modal com 3 espaços de foto por parceiro — pra guardar a arte e depois baixar/compartilhar no Instagram/WhatsApp. */
function FotosParceria({ parceria, aoFechar }: { parceria: ParceriaAdmin; aoFechar: () => void }) {
  const salvar = useSalvarFotosParceria()
  const [erro, setErro] = useState<string | null>(null)
  async function trocar(campo: 'foto1' | 'foto2' | 'foto3', arquivo: File) {
    setErro(null)
    try {
      const dataUrl = await comprimirFoto(arquivo)
      salvar.mutate({ id: parceria.id, dados: { foto1: parceria.foto1, foto2: parceria.foto2, foto3: parceria.foto3, [campo]: dataUrl } })
    } catch (e) { setErro(e instanceof Error ? e.message : 'Falha ao ler a foto.') }
  }
  function remover(campo: 'foto1' | 'foto2' | 'foto3') {
    salvar.mutate({ id: parceria.id, dados: { foto1: parceria.foto1, foto2: parceria.foto2, foto3: parceria.foto3, [campo]: null } })
  }
  return (
    <Modal aberto titulo={`Fotos — ${parceria.nome}`} aoFechar={aoFechar}>
      <div className="space-y-3">
        <p className="text-sm text-ink-muted">Guarde aqui as artes desse parceiro pra entrar quando quiser e postar no Instagram/WhatsApp — não aparece pro cliente no Portal.</p>
        {(erro || salvar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(salvar.error)}</Alerta>}
        <div className="grid grid-cols-3 gap-3">
          <SlotFoto rotulo="Foto 1" valor={parceria.foto1} carregando={salvar.isPending} aoTrocar={(f) => void trocar('foto1', f)} aoRemover={() => remover('foto1')} />
          <SlotFoto rotulo="Foto 2" valor={parceria.foto2} carregando={salvar.isPending} aoTrocar={(f) => void trocar('foto2', f)} aoRemover={() => remover('foto2')} />
          <SlotFoto rotulo="Foto 3" valor={parceria.foto3} carregando={salvar.isPending} aoTrocar={(f) => void trocar('foto3', f)} aoRemover={() => remover('foto3')} />
        </div>
      </div>
    </Modal>
  )
}

function BotaoAtivo({ parceria }: { parceria: ParceriaAdmin }) {
  const alternar = useAlternarAtivoParceria()
  return (
    <button type="button" onClick={() => alternar.mutate({ id: parceria.id, ativo: !parceria.ativo })} disabled={alternar.isPending}>
      <Distintivo tom={parceria.ativo ? 'ok' : 'neutro'}>{parceria.ativo ? 'Ativo' : 'Inativo'}</Distintivo>
    </button>
  )
}

/** Admin: importação em massa (Leveduca) + cadastro manual (Servnet) + fotos pra compartilhar nas redes. */
export function ParceriasAdmin({ negocioId }: { negocioId: string }) {
  const parceriasQ = useParceriasAdmin()
  const [janela, setJanela] = useState<{ parceria?: ParceriaAdmin } | null>(null)
  const [fotosDe, setFotosDe] = useState<ParceriaAdmin | null>(null)
  const [buscaLeveduca, setBuscaLeveduca] = useState('')
  const todas = (parceriasQ.data ?? []).filter((p) => p.negocio_id === negocioId)
  const leveduca = todas.filter((p) => p.origem === 'leveduca')
  const servnet = todas.filter((p) => p.origem === 'servnet')
  const categorias = new Set(leveduca.map((p) => p.categoria).filter(Boolean))
  const buscaNorm = normalizar(buscaLeveduca)
  const encontrados = buscaNorm.length === 0 ? leveduca : leveduca.filter((p) => normalizar(p.nome).includes(buscaNorm) || normalizar(p.categoria ?? '').includes(buscaNorm))
  // usa a instância mais atual (fotos podem ter mudado após salvar)
  const fotosDeAtual = fotosDe ? (todas.find((p) => p.id === fotosDe.id) ?? fotosDe) : null
  return (
    <div className="space-y-4">
      <ImportarLeveduca negocioId={negocioId} />
      <Cartao className="p-0">
        <div className="border-b border-line px-6 py-3">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Clube de benefícios Leveduca</h2>
          <p className="text-xs text-ink-muted">{leveduca.length} parceiro(s) · {categorias.size} categoria(s)</p>
        </div>
        {leveduca.length === 0 ? <p className="px-6 py-6 text-sm text-ink-muted">Nenhuma lista importada ainda.</p> : (
          <div className="px-6 py-4">
            <Campo rotulo="Buscar (nome ou categoria)" value={buscaLeveduca} onChange={(e) => setBuscaLeveduca(e.target.value)} placeholder="deixe em branco pra ver todos…" />
            {encontrados.length === 0 ? <p className="mt-3 text-sm text-ink-muted">Nada encontrado.</p> : (
              <ul className="mt-3 max-h-[32rem] divide-y divide-line overflow-y-auto">
                {encontrados.map((p) => (
                  <li key={p.id} className="flex items-center justify-between gap-3 py-2 text-sm">
                    <span>{p.nome} <span className="text-xs text-ink-muted">— {p.categoria ?? 'sem categoria'}</span></span>
                    <div className="flex items-center gap-3">
                      <button type="button" onClick={() => setFotosDe(p)} className="text-brand-700 hover:underline">Fotos {[p.foto1, p.foto2, p.foto3].filter(Boolean).length > 0 ? `(${[p.foto1, p.foto2, p.foto3].filter(Boolean).length})` : ''}</button>
                      <BotaoAtivo parceria={p} />
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
      </Cartao>
      <Cartao className="p-0">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-6 py-3">
          <div>
            <h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Parceiros próprios da Servnet</h2>
            <p className="text-xs text-ink-muted">Acordos locais que você negociou, além da lista da Leveduca.</p>
          </div>
          <Botao onClick={() => setJanela({})}>Novo parceiro</Botao>
        </div>
        {servnet.length === 0 ? <p className="px-6 py-6 text-sm text-ink-muted">Nenhum parceiro próprio cadastrado ainda.</p> : (
          <ul className="divide-y divide-line">
            {servnet.map((p) => (
              <li key={p.id} className="flex items-center justify-between gap-3 px-6 py-3 text-sm">
                <button type="button" onClick={() => setJanela({ parceria: p })} className="text-left hover:underline">
                  <span className="font-medium">{p.nome}</span> <span className="text-ink-muted">— {p.beneficio}</span>
                </button>
                <div className="flex items-center gap-3">
                  <button type="button" onClick={() => setFotosDe(p)} className="text-xs text-brand-700 hover:underline">Fotos {[p.foto1, p.foto2, p.foto3].filter(Boolean).length > 0 ? `(${[p.foto1, p.foto2, p.foto3].filter(Boolean).length})` : ''}</button>
                  <BotaoAtivo parceria={p} />
                </div>
              </li>
            ))}
          </ul>
        )}
      </Cartao>
      <Modal aberto={janela !== null} aoFechar={() => setJanela(null)} titulo={janela?.parceria ? 'Editar parceiro' : 'Novo parceiro'}>
        {janela && <FormParceria negocioId={negocioId} parceria={janela.parceria} aoConcluir={() => setJanela(null)} />}
      </Modal>
      {fotosDeAtual && <FotosParceria parceria={fotosDeAtual} aoFechar={() => setFotosDe(null)} />}
    </div>
  )
}
