import { useEffect, useMemo, useRef, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { Selecao } from '../../../core/ui/Selecao'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, hojeISO } from '../../../core/formatos'
import { supabase } from '../../../core/supabase/client'
import { useNegocios } from '../../negocios/api'
import { usePessoas, useAtualizarPessoa } from '../../pessoas/api'
import { formatarTelefone, somenteDigitos, type Pessoa } from '../../pessoas/tipos'
import { useCriarLancamento } from '../../lancamentos/api'
import { useCriarDisparo, useDisparos, useItensDisparo, useModelosDisparo, useProcessarDisparos, useReenviarFalhas, useSalvarModeloDisparo } from '../api'
import { lerTextoPdf, ROTULO_STATUS_DISPARO, type Disparo } from '../tipos'

interface Alvo { pessoa: Pessoa; marcado: boolean; telefoneNovo: string; valor: string; vencimento: string }

/** Chave de match no PDF: login do servidor ou, na falta, o próprio nome quando é um login (sem espaços). */
function chaveLogin(p: Pessoa): string | null {
  if (p.login_servidor) return p.login_servidor.toLowerCase()
  const nome = p.nome.trim()
  return !nome.includes(' ') && nome.length >= 4 ? nome.toLowerCase() : null
}

function primeiroNome(nome: string) { return nome.trim().split(/\s+/)[0] ?? nome }

/** Progresso e histórico de um disparo, com reenvio das falhas. */
function DetalheDisparo({ disparo, nomePessoa, aoFechar }: { disparo: Disparo; nomePessoa: Map<string, string>; aoFechar: () => void }) {
  const itens = useItensDisparo(disparo.id, true)
  const processar = useProcessarDisparos()
  const reenviar = useReenviarFalhas()
  const ultimoTick = useRef(0)
  const pendentes = (itens.data ?? []).filter((i) => i.status === 'pendente').length
  const erros = (itens.data ?? []).filter((i) => i.status === 'erro').length
  const reprocessar = processar.mutate
  // fila anda 3 por chamada da Edge; enquanto houver pendentes, re-aciona a cada 50 s
  useEffect(() => {
    if (pendentes > 0 && Date.now() - ultimoTick.current > 50000) {
      ultimoTick.current = Date.now()
      reprocessar()
    }
  }, [pendentes, itens.dataUpdatedAt, reprocessar])
  return (
    <div className="space-y-3">
      <p className="text-sm text-ink-muted">{disparo.modelo_nome} · {formatarData(disparo.criado_em.slice(0, 10))}{pendentes > 0 && ` · enviando… (${pendentes} na fila, ~15 s entre mensagens)`}</p>
      <div className="max-h-80 overflow-y-auto rounded-md border border-line">
        <table className="w-full text-sm">
          <tbody>
            {(itens.data ?? []).map((i) => (
              <tr key={i.id} className="border-b border-line last:border-0">
                <td className="px-3 py-2">{nomePessoa.get(i.pessoa_id) ?? '—'}</td>
                <td className="whitespace-nowrap px-3 py-2 text-ink-muted">{i.numero_destino}</td>
                <td className="whitespace-nowrap px-3 py-2"><Distintivo tom={i.status === 'enviado' ? 'ok' : i.status === 'erro' ? 'alerta' : 'info'}>{ROTULO_STATUS_DISPARO[i.status]}</Distintivo>{i.erro && <p className="max-w-56 truncate text-xs text-red-700" title={i.erro}>{i.erro}</p>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="flex justify-end gap-2">
        {erros > 0 && pendentes === 0 && (
          <Botao variante="secundario" carregando={reenviar.isPending} onClick={() => reenviar.mutate(disparo.id, { onSuccess: () => processar.mutate() })}>Reenviar falhas ({erros})</Botao>
        )}
        <Botao onClick={aoFechar}>Fechar</Botao>
      </div>
    </div>
  )
}

export function DisparosPage() {
  const negocios = useNegocios()
  const pessoas = usePessoas()
  const modelos = useModelosDisparo()
  const disparos = useDisparos()
  const criar = useCriarDisparo()
  const processar = useProcessarDisparos()
  const salvarModelo = useSalvarModeloDisparo()
  const atualizarPessoa = useAtualizarPessoa()
  const criarLancamento = useCriarLancamento()

  const [negocioId, setNegocioId] = useState('')
  const [modeloId, setModeloId] = useState('')
  const [texto, setTexto] = useState('')
  const [alvos, setAlvos] = useState<Alvo[]>([])
  const [naoReconhecidos, setNaoReconhecidos] = useState(0)
  const [lendoPdf, setLendoPdf] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const [adicionarId, setAdicionarId] = useState('')
  const [lancarCobranca, setLancarCobranca] = useState(false)
  const [detalhe, setDetalhe] = useState<Disparo | null>(null)
  const [disparando, setDisparando] = useState(false)

  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const comLogin = useMemo(() => (pessoas.data ?? []).filter((p) => p.ativo && chaveLogin(p)), [pessoas.data])
  const marcados = alvos.filter((a) => a.marcado)
  const modelo = (modelos.data ?? []).find((m) => m.id === modeloId)

  function escolherModelo(id: string) {
    setModeloId(id)
    const m = (modelos.data ?? []).find((x) => x.id === id)
    if (m) setTexto(m.texto)
  }

  async function aoEscolherPdf(arquivo: File) {
    setLendoPdf(true); setErro(null); setAviso(null)
    try {
      const textoPdf = (await lerTextoPdf(await arquivo.arrayBuffer())).toLowerCase()
      const achados = comLogin.filter((p) => textoPdf.includes(chaveLogin(p)!))
      setAlvos(achados.map((p) => ({ pessoa: p, marcado: Boolean(p.telefone) && p.receber_avisos, telefoneNovo: '', valor: '', vencimento: hojeISO() })))
      setNaoReconhecidos(0)
      if (achados.length === 0) setAviso('Nenhum login do cadastro foi encontrado no PDF. Vincule o "Login do servidor" nas pessoas (editar pessoa) e tente de novo.')
      else setAviso(`${achados.length} cliente(s) reconhecido(s) pelo login do servidor.`)
    } catch (e) {
      setErro(mensagemDeErro(e))
    } finally {
      setLendoPdf(false)
    }
  }

  function adicionarManual() {
    const p = (pessoas.data ?? []).find((x) => x.id === adicionarId)
    if (!p || alvos.some((a) => a.pessoa.id === p.id)) return
    setAlvos((xs) => [...xs, { pessoa: p, marcado: true, telefoneNovo: '', valor: '', vencimento: hojeISO() }])
    setAdicionarId('')
  }

  async function salvarTelefone(a: Alvo) {
    const tel = somenteDigitos(a.telefoneNovo)
    if (tel.length < 10 || tel.length > 13) { setErro('Telefone com DDD, 10 ou 11 dígitos.'); return }
    const p = a.pessoa
    const salvo = await atualizarPessoa.mutateAsync({ id: p.id, tipo: p.tipo, nome: p.nome, documento: p.documento, email: p.email, telefone: tel, login_servidor: p.login_servidor, data_nascimento: p.data_nascimento, observacao: p.observacao, ativo: p.ativo, receber_avisos: p.receber_avisos })
    setAlvos((xs) => xs.map((x) => (x.pessoa.id === p.id ? { ...x, pessoa: { ...p, telefone: (salvo as Pessoa).telefone ?? tel }, marcado: true, telefoneNovo: '' } : x)))
  }

  async function disparar() {
    setErro(null); setAviso(null)
    if (!negocioId) { setErro('Escolha o negócio (define a instância do WhatsApp).'); return }
    if (texto.trim().length < 10) { setErro('Escreva a mensagem (mínimo 10 caracteres).'); return }
    if (marcados.length === 0 || marcados.length > 30) { setErro('Marque de 1 a 30 clientes.'); return }
    if (marcados.some((a) => !a.pessoa.telefone)) { setErro('Há cliente marcado sem telefone: informe e salve o telefone antes.'); return }
    setDisparando(true)
    try {
      let cobrancasCriadas = 0
      if (lancarCobranca) {
        const semDados = marcados.filter((a) => !(Number(a.valor.replace(',', '.')) > 0) || !a.vencimento)
        if (semDados.length > 0) { setErro(`Informe valor e vencimento de: ${semDados.map((a) => primeiroNome(a.pessoa.nome)).join(', ')}.`); setDisparando(false); return }
        const neg = (negocios.data ?? []).find((n) => n.id === negocioId)
        if (!neg?.conta_padrao_id || !neg?.categoria_receita_id) { setErro('O negócio precisa de conta padrão e categoria de receita (tela Negócios) para lançar a cobrança.'); setDisparando(false); return }
        for (const a of marcados) {
          const v = Math.round(Number(a.valor.replace(',', '.')) * 100) / 100
          const { data: existentes } = await supabase.from('lancamentos').select('id').eq('pessoa_id', a.pessoa.id).eq('tipo', 'receita').eq('status', 'previsto').eq('data_vencimento', a.vencimento).limit(1)
          if ((existentes ?? []).length > 0) continue // já lançado: não duplica
          await criarLancamento.mutateAsync({
            tipo: 'receita', descricao: `Mensalidade servidor · ${primeiroNome(a.pessoa.nome)}`, valor: v,
            data_competencia: a.vencimento, data_vencimento: a.vencimento, data_efetivacao: null,
            conta_id: neg.conta_padrao_id, conta_destino_id: null, categoria_id: neg.categoria_receita_id,
            observacao: `Login: ${a.pessoa.login_servidor ?? '—'}`, negocio_id: negocioId, pessoa_id: a.pessoa.id, contrato_id: null,
            recorrente: true, periodicidade: 'mensal', numero_parcelas: null, data_fim_recorrencia: null,
          })
          cobrancasCriadas++
        }
      }
      const d = await criar.mutateAsync({
        negocio_id: negocioId,
        modelo_nome: modelo?.nome ?? 'Mensagem avulsa',
        itens: marcados.map((a) => ({ pessoa_id: a.pessoa.id, mensagem: texto.replaceAll('{nome}', primeiroNome(a.pessoa.nome)) })),
      })
      processar.mutate()
      setDetalhe(d)
      setAlvos([])
      setAviso(lancarCobranca ? `Disparo iniciado. Cobranças novas lançadas: ${cobrancasCriadas} (fixas mensais, sem marcar como pagas).` : 'Disparo iniciado.')
    } catch (e) {
      setErro(mensagemDeErro(e))
    } finally {
      setDisparando(false)
    }
  }

  return (
    <>
      <CabecalhoPagina titulo="Disparos" descricao="Mensagens WhatsApp em lote a partir do PDF de receitas do servidor" />
      {erro && <div className="mb-4"><Alerta tipo="erro">{erro}</Alerta></div>}
      {aviso && <div className="mb-4"><Alerta tipo="info">{aviso}</Alerta></div>}

      <Cartao className="mb-4 space-y-4 p-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Selecao rotulo="Negócio (instância do WhatsApp)" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(negocios.data ?? []).filter((n) => n.ativo).map((n) => ({ valor: n.id, rotulo: n.nome }))]} value={negocioId} onChange={(e) => setNegocioId(e.target.value)} />
          <div>
            <label className="mb-1 block text-sm font-medium text-ink">PDF de receitas (logins do servidor)</label>
            <input type="file" accept="application/pdf" disabled={lendoPdf} onChange={(e) => { const f = e.target.files?.[0]; if (f) void aoEscolherPdf(f); e.target.value = '' }} className="block w-full text-sm file:mr-3 file:rounded-md file:border-0 file:bg-brand-600 file:px-3 file:py-2 file:text-sm file:font-medium file:text-white hover:file:bg-brand-700" />
            {lendoPdf && <p className="mt-1 text-xs text-ink-muted">Lendo o PDF…</p>}
          </div>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <Selecao rotulo="Modelo de mensagem" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(modelos.data ?? []).filter((m) => m.ativo).map((m) => ({ valor: m.id, rotulo: m.nome }))]} value={modeloId} onChange={(e) => escolherModelo(e.target.value)} />
            {modelo && texto !== modelo.texto && (
              <Botao variante="secundario" carregando={salvarModelo.isPending} onClick={() => salvarModelo.mutate({ id: modelo.id, nome: modelo.nome, texto })}>Salvar alterações no modelo</Botao>
            )}
          </div>
          <AreaTexto rotulo="Mensagem ({nome} vira o primeiro nome do cliente)" rows={6} maxLength={2000} value={texto} onChange={(e) => setTexto(e.target.value)} />
        </div>
        <div className="rounded-md border border-line bg-surface/60 p-3">
          <label className="flex items-center gap-2 text-sm font-medium">
            <input type="checkbox" checked={lancarCobranca} onChange={(e) => setLancarCobranca(e.target.checked)} className="size-4 accent-brand-600" />
            Lançar cobrança no contas a receber (fixa mensal, sem marcar como paga; não duplica se já existir no vencimento)
          </label>
          {lancarCobranca && <p className="mt-1 text-xs text-ink-muted">Cada cliente tem seu valor e vencimento: preencha nas colunas da lista abaixo.</p>}
        </div>
      </Cartao>

      <Cartao className="mb-4 p-0">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-4 py-3">
          <span className="text-sm font-medium">Destinatários · {marcados.length} marcado(s) de {alvos.length} (máx. 30){naoReconhecidos > 0 && ` · ${naoReconhecidos} não reconhecidos`}</span>
          <div className="flex items-center gap-2">
            <select aria-label="Adicionar cliente manualmente" value={adicionarId} onChange={(e) => setAdicionarId(e.target.value)} className="h-9 rounded-md border border-line bg-white px-2 text-sm">
              <option value="">Adicionar cliente…</option>
              {(pessoas.data ?? []).filter((p) => p.ativo && !alvos.some((a) => a.pessoa.id === p.id)).map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
            </select>
            <Botao variante="secundario" onClick={adicionarManual} disabled={!adicionarId}>Adicionar</Botao>
          </div>
        </div>
        {alvos.length === 0 ? (
          <p className="px-6 py-10 text-center text-sm text-ink-muted">Envie o PDF (ou adicione clientes manualmente) para montar a lista.</p>
        ) : (
          <div className="overflow-x-auto"><table className="w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2"></th><th className="px-4 py-2 font-medium">Cliente</th><th className="px-4 py-2 font-medium">Login</th><th className="px-4 py-2 font-medium">Telefone</th>{lancarCobranca && <><th className="px-4 py-2 font-medium">Valor (R$)</th><th className="px-4 py-2 font-medium">Vencimento</th></>}<th className="px-4 py-2"></th></tr></thead>
            <tbody>
              {alvos.map((a) => (
                <tr key={a.pessoa.id} className="border-b border-line last:border-0">
                  <td className="px-4 py-2"><input type="checkbox" checked={a.marcado} disabled={!a.pessoa.telefone} onChange={(e) => setAlvos((xs) => xs.map((x) => (x.pessoa.id === a.pessoa.id ? { ...x, marcado: e.target.checked } : x)))} className="size-4 accent-brand-600" /></td>
                  <td className="px-4 py-2 font-medium">{a.pessoa.nome}{!a.pessoa.receber_avisos && <span className="ml-2 text-xs text-amber-700">avisos desativados</span>}</td>
                  <td className="px-4 py-2 font-mono text-xs text-ink-muted">{a.pessoa.login_servidor ?? '—'}</td>
                  <td className="px-4 py-2">
                    {a.pessoa.telefone ? formatarTelefone(a.pessoa.telefone) : (
                      <span className="flex items-center gap-2">
                        <input value={a.telefoneNovo} onChange={(e) => setAlvos((xs) => xs.map((x) => (x.pessoa.id === a.pessoa.id ? { ...x, telefoneNovo: e.target.value } : x)))} placeholder="(11) 99999-9999" className="h-8 w-40 rounded-md border border-line bg-white px-2 text-sm" />
                        <Botao variante="secundario" carregando={atualizarPessoa.isPending} disabled={!a.telefoneNovo.trim()} onClick={() => void salvarTelefone(a)}>Salvar</Botao>
                      </span>
                    )}
                  </td>
                  {lancarCobranca && (
                    <>
                      <td className="px-4 py-2"><input type="number" step="0.01" min="0.01" value={a.valor} onChange={(e) => setAlvos((xs) => xs.map((x) => (x.pessoa.id === a.pessoa.id ? { ...x, valor: e.target.value } : x)))} placeholder="0,00" className="h-8 w-24 rounded-md border border-line bg-white px-2 text-sm" /></td>
                      <td className="px-4 py-2"><input type="date" value={a.vencimento} onChange={(e) => setAlvos((xs) => xs.map((x) => (x.pessoa.id === a.pessoa.id ? { ...x, vencimento: e.target.value } : x)))} className="h-8 w-36 rounded-md border border-line bg-white px-2 text-sm" /></td>
                    </>
                  )}
                  <td className="px-4 py-2 text-right">
                    <button type="button" aria-label={`Remover ${a.pessoa.nome}`} className="text-ink-muted hover:text-red-700" onClick={() => setAlvos((xs) => xs.filter((x) => x.pessoa.id !== a.pessoa.id))}>×</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table></div>
        )}
        <div className="flex justify-end border-t border-line px-4 py-3">
          <Botao carregando={disparando} disabled={marcados.length === 0} onClick={() => void disparar()}>Disparar ({marcados.length})</Botao>
        </div>
      </Cartao>

      <Cartao className="p-0">
        <p className="border-b border-line px-4 py-3 text-sm font-medium">Histórico de disparos</p>
        {(disparos.data ?? []).length === 0 ? <p className="px-6 py-8 text-center text-sm text-ink-muted">Nenhum disparo ainda.</p> : (
          <ul className="divide-y divide-line">
            {(disparos.data ?? []).map((d) => (
              <li key={d.id}>
                <button type="button" className="flex w-full items-center justify-between px-4 py-3 text-left text-sm hover:bg-surface" onClick={() => setDetalhe(d)}>
                  <span>{d.modelo_nome}</span>
                  <span className="text-ink-muted">{formatarData(d.criado_em.slice(0, 10))}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </Cartao>

      <Modal aberto={detalhe !== null} aoFechar={() => setDetalhe(null)} largura="md" titulo="Disparo">
        {detalhe && <DetalheDisparo disparo={detalhe} nomePessoa={nomePessoa} aoFechar={() => setDetalhe(null)} />}
      </Modal>
    </>
  )
}
