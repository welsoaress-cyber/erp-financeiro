import { useMemo, useState, type FormEvent } from 'react'
import { Link, useParams } from 'react-router'
import { Cartao } from '../../core/ui/Cartao'
import { Alerta } from '../../core/ui/Alerta'
import { Botao } from '../../core/ui/Botao'
import { Campo } from '../../core/ui/Campo'
import { Carregando } from '../../core/ui/Carregando'
import { Distintivo } from '../../core/ui/Distintivo'
import { Selecao } from '../../core/ui/Selecao'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../core/formatos'
import { formatarDocumento, formatarTelefone, somenteDigitos } from '../../modules/pessoas/tipos'
import { usePortal } from '../contexto'
import { useAceitarContrato, useContratosCliente, useEscolherPresente, useFaturas, useIndicacoesCliente, useIndicar, useMeusAceites, usePagamentos, usePagarComPix, usePresentesIndicacao, usePromocoesCliente, useProximasFaturas, useTermoContrato } from '../api'
import { ROTULO_INDICACAO, ROTULO_SITUACAO, ROTULO_STATUS_CONTRATO, TOM, codigoContrato, linkIndicacao, type Fatura, type SituacaoFatura } from '../tipos'
import { Indicador, Titulo } from './comum'

function BotaoPix({ fatura }: { fatura: Fatura }) {
  const pagar = usePagarComPix()
  const [pix, setPix] = useState<{ copia_cola: string; ticket_url?: string | null } | null>(null)
  const [copiado, setCopiado] = useState(false)
  async function copiar(codigo: string) { try { await navigator.clipboard.writeText(codigo); setCopiado(true); setTimeout(() => setCopiado(false), 2000) } catch { /* sem clipboard */ } }
  if (fatura.situacao === 'paga' || fatura.situacao === 'gratis') return null
  if (pix) {
    return (
      <div className="mt-2 rounded-md border border-line bg-surface p-3 text-left">
        <p className="text-xs font-semibold uppercase tracking-wide text-ink-muted">Pix copia e cola</p>
        <p className="mt-1 break-all font-mono text-[11px]">{pix.copia_cola}</p>
        <span className="mt-2 flex flex-wrap gap-2">
          <Botao onClick={() => void copiar(pix.copia_cola)}>{copiado ? 'Copiado!' : 'Copiar código'}</Botao>
          {pix.ticket_url && <a href={pix.ticket_url} target="_blank" rel="noreferrer" className="inline-flex h-10 items-center rounded-md border border-line px-4 text-sm hover:bg-white/5">Ver QR Code</a>}
        </span>
        <p className="mt-2 text-xs text-ink-muted">Depois do pagamento a fatura baixa sozinha em alguns minutos.</p>
      </div>
    )
  }
  return (
    <div className="mt-1 text-left">
      {pagar.error != null && <p className="mb-1 text-xs text-red-400">{mensagemDeErro(pagar.error)}</p>}
      <Botao variante="secundario" carregando={pagar.isPending} onClick={() => pagar.mutate({ lancamentoId: fatura.id }, { onSuccess: setPix })}>Pagar com Pix</Botao>
    </div>
  )
}

export function PortalFaturasPage() {
  const faturas = useFaturas()
  const proximas = useProximasFaturas()
  const [filtro, setFiltro] = useState<SituacaoFatura | ''>('')
  const lista = (faturas.data ?? []).filter((f) => !filtro || f.situacao === filtro)
  return (
    <div className="space-y-6">
      <Titulo acao={<select aria-label="Filtrar faturas" value={filtro} onChange={(e) => setFiltro(e.target.value as SituacaoFatura | '')} className="h-9 rounded-md border border-line bg-white px-3 text-sm"><option value="">Todas</option><option value="pendente">Em aberto</option><option value="vencida">Vencidas</option><option value="paga">Pagas</option></select>}>Faturas</Titulo>
      <Cartao className="p-0">
        {faturas.isPending ? <div className="p-6"><Carregando /></div> : faturas.isError ? <div className="p-6"><Alerta tipo="erro">{mensagemDeErro(faturas.error)}</Alerta></div> : lista.length === 0 ? <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhuma fatura.</p> : (
          <div className="overflow-x-auto"><table className="w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-3">Vencimento</th><th className="px-4 py-3">Plano</th><th className="px-4 py-3 text-right">Valor</th><th className="px-4 py-3">Situação</th><th className="px-4 py-3"></th></tr></thead>
            <tbody>{lista.map((f) => (
              <tr key={f.id} className="border-b border-line last:border-0">
                <td className="px-4 py-3 tabular-nums">{formatarData(f.data_vencimento)}</td>
                <td className="px-4 py-3">{f.plano} <span className="font-mono text-xs text-ink-muted">{codigoContrato(f.contrato_codigo)}</span>{f.observacao && <p className="text-xs text-green-700">{f.observacao}</p>}</td>
                <td className="px-4 py-3 text-right tabular-nums">{formatarMoeda(f.valor)}</td>
                <td className="px-4 py-3"><Distintivo tom={TOM[f.situacao]}>{ROTULO_SITUACAO[f.situacao]}</Distintivo>{f.data_efetivacao && <p className="text-xs text-ink-muted">em {formatarData(f.data_efetivacao)}</p>}</td>
                <td className="px-4 py-3 text-right"><Link to={`/portal/faturas/${f.id}`} className="text-brand-700 hover:underline whitespace-nowrap">{f.situacao === 'paga' ? 'Recibo' : 'Boleto / PDF'}</Link><BotaoPix fatura={f} /></td>
              </tr>))}</tbody>
          </table></div>
        )}
      </Cartao>
      <Cartao>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-ink-muted">Próximas faturas (previsão)</h2>
        {proximas.isPending ? <Carregando /> : (proximas.data ?? []).length === 0 ? <p className="text-sm text-ink-muted">Nenhuma cobrança prevista para os próximos meses.</p> : (
          <ul className="divide-y divide-line">{(proximas.data ?? []).map((p, i) => <li key={i} className="flex items-center justify-between py-2 text-sm"><span>{formatarData(p.data_vencimento)} · {p.plano} <span className="font-mono text-xs text-ink-muted">{codigoContrato(p.contrato_codigo)}</span></span><span className="tabular-nums">{formatarMoeda(p.valor)}</span></li>)}</ul>
        )}
        <p className="mt-2 text-xs text-ink-muted">Valores previstos pelo seu plano; descontos do Indique e Ganhe já considerados.</p>
      </Cartao>
    </div>
  )
}

/** Boleto/recibo em PDF: página pronta para impressão (Salvar como PDF no navegador). Sem gateway de pagamento. */
export function PortalFaturaPdfPage() {
  const { id } = useParams()
  const r = usePortal()
  const faturas = useFaturas()
  const f = (faturas.data ?? []).find((x) => x.id === id)
  if (faturas.isPending) return <Carregando />
  if (!f) return <Alerta tipo="erro">Fatura não encontrada.</Alerta>
  return <DocumentoFatura fatura={f} cliente={r.pessoa} />
}
function DocumentoFatura({ fatura: f, cliente }: { fatura: Fatura; cliente: { nome: string; documento: string | null; telefone: string | null } }) {
  const paga = f.situacao === 'paga'
  return (
    <div>
      <div className="mb-4 flex gap-2 print:hidden"><Botao onClick={() => window.print()}>Baixar PDF / Imprimir</Botao><Link to="/portal/faturas"><Botao variante="secundario">Voltar</Botao></Link></div>
      <div className="mx-auto max-w-2xl rounded-lg border border-line bg-white p-8 print:border-0 print:p-0">
        <div className="flex items-start justify-between border-b border-line pb-4">
          <div><p className="text-lg font-semibold">{f.negocio}</p><p className="text-sm text-ink-muted">{paga ? 'Recibo de pagamento' : 'Fatura'} · contrato {codigoContrato(f.contrato_codigo)}</p></div>
          <Distintivo tom={TOM[f.situacao]}>{ROTULO_SITUACAO[f.situacao]}</Distintivo>
        </div>
        <dl className="mt-4 grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
          <dt className="text-ink-muted">Cliente</dt><dd>{cliente.nome}{cliente.documento && ` · ${formatarDocumento(cliente.documento)}`}</dd>
          <dt className="text-ink-muted">Plano</dt><dd>{f.plano}</dd>
          <dt className="text-ink-muted">Referente a</dt><dd>{f.descricao}</dd>
          <dt className="text-ink-muted">Vencimento</dt><dd>{formatarData(f.data_vencimento)}</dd>
          {f.data_efetivacao && <><dt className="text-ink-muted">Pago em</dt><dd>{formatarData(f.data_efetivacao)}</dd></>}
          <dt className="text-ink-muted">Valor</dt><dd className="text-lg font-semibold">{formatarMoeda(f.valor)}</dd>
          {f.observacao && <><dt className="text-ink-muted">Observação</dt><dd>{f.observacao}</dd></>}
        </dl>
        {!paga && (
          <div className="mt-6 rounded-md border border-line bg-surface p-4 text-sm">
            <p className="font-semibold">Como pagar</p>
            {f.chave_pix ? <p className="mt-1">Pix: <span className="font-mono">{f.chave_pix}</span></p> : <p className="mt-1 text-ink-muted">Fale com o provedor para as formas de pagamento.</p>}
            {f.instrucoes_pagamento && <p className="mt-1 whitespace-pre-line">{f.instrucoes_pagamento}</p>}
            <p className="mt-2 text-xs text-ink-muted">Este documento não é um boleto bancário registrado. Após o pagamento, o provedor confirma e a fatura aparece como paga.</p>
          </div>
        )}
        <p className="mt-6 text-xs text-ink-muted">Emitido em {formatarData(new Date().toISOString().slice(0, 10))} pelo portal do cliente.</p>
      </div>
    </div>
  )
}

export function PortalPagamentosPage() {
  const pagamentos = usePagamentos()
  const total = (pagamentos.data ?? []).reduce((s, p) => s + p.valor, 0)
  return (
    <div className="space-y-4">
      <Titulo>Pagamentos</Titulo>
      <Cartao className="p-0">
        {pagamentos.isPending ? <div className="p-6"><Carregando /></div> : (pagamentos.data ?? []).length === 0 ? <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhum pagamento registrado.</p> : (
          <div className="overflow-x-auto"><table className="w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-3">Data</th><th className="px-4 py-3">Referente a</th><th className="px-4 py-3">Forma</th><th className="px-4 py-3 text-right">Valor</th><th className="px-4 py-3">Status</th></tr></thead>
            <tbody>{(pagamentos.data ?? []).map((p) => <tr key={p.id} className="border-b border-line last:border-0"><td className="px-4 py-3 tabular-nums">{formatarData(p.data_pagamento)}</td><td className="px-4 py-3">{p.descricao}</td><td className="px-4 py-3 text-ink-muted">{p.forma}</td><td className="px-4 py-3 text-right tabular-nums">{formatarMoeda(p.valor)}</td><td className="px-4 py-3"><Distintivo tom="ok">Confirmado</Distintivo></td></tr>)}</tbody>
            <tfoot><tr><td colSpan={3} className="px-4 py-3 text-right text-ink-muted">Total pago</td><td className="px-4 py-3 text-right font-semibold tabular-nums">{formatarMoeda(total)}</td><td /></tr></tfoot>
          </table></div>
        )}
      </Cartao>
    </div>
  )
}

function AceiteContrato() {
  const aceites = useMeusAceites()
  const aceitar = useAceitarContrato()
  const [lendo, setLendo] = useState<string | null>(null)
  const termo = useTermoContrato(lendo)
  const pendentes = (aceites.data ?? []).filter((a) => !a.aceito)
  const feitos = (aceites.data ?? []).filter((a) => a.aceito)
  if ((aceites.data ?? []).length === 0) return null
  return (
    <Cartao>
      <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Termo de adesão</h2>
      {aceitar.error != null && <Alerta tipo="erro">{mensagemDeErro(aceitar.error)}</Alerta>}
      {pendentes.map((a) => (
        <div key={a.contrato_id} className="mb-2 rounded-md border border-amber-400/40 bg-amber-500/10 p-3 text-sm">
          <p className="font-medium">Contrato {codigoContrato(a.codigo)} · {a.plano} — aguardando o seu aceite digital.</p>
          {lendo === a.contrato_id ? (
            <>
              <pre className="mt-2 max-h-64 overflow-y-auto whitespace-pre-wrap rounded-md bg-surface p-3 font-sans text-xs">{termo.data ?? 'Carregando…'}</pre>
              <span className="mt-2 flex gap-2">
                <Botao carregando={aceitar.isPending} onClick={() => aceitar.mutate({ contratoId: a.contrato_id }, { onSuccess: () => setLendo(null) })}>Li e aceito</Botao>
                <Botao variante="secundario" onClick={() => setLendo(null)}>Fechar</Botao>
              </span>
              <p className="mt-1 text-xs text-ink-muted">O aceite registra data, hora, IP e o texto exato — vale como concordância com o termo.</p>
            </>
          ) : (
            <Botao variante="secundario" onClick={() => setLendo(a.contrato_id)}>Ler o termo e aceitar</Botao>
          )}
        </div>
      ))}
      {feitos.map((a) => (
        <p key={a.contrato_id} className="text-xs text-ink-muted">Contrato {codigoContrato(a.codigo)} aceito em {a.data_aceite ? formatarData(a.data_aceite.slice(0, 10)) : '—'}. ✔</p>
      ))}
    </Cartao>
  )
}

export function PortalPlanoPage() {
  const contratos = useContratosCliente()
  const r = usePortal()
  const per = { mensal: 'por mês', anual: 'por ano', unico: 'único' }
  return (
    <div className="space-y-4">
      <Titulo>Meu plano</Titulo>
      <AceiteContrato />
      {contratos.isPending ? <Carregando /> : (contratos.data ?? []).length === 0 ? <Alerta tipo="info">Nenhum plano contratado.</Alerta> : (contratos.data ?? []).map((c) => (
        <Cartao key={c.id}>
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div><p className="text-lg font-semibold">{c.plano}</p><p className="text-sm text-ink-muted">{c.negocio} · contrato {codigoContrato(c.codigo)}{c.plano_descricao ? ` · ${c.plano_descricao}` : ''}</p></div>
            <Distintivo tom={c.status === 'ativo' ? 'ok' : c.status === 'suspenso' ? 'alerta' : 'neutro'}>{ROTULO_STATUS_CONTRATO[c.status]}</Distintivo>
          </div>
          <dl className="mt-4 grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
            <dt className="text-ink-muted">Valor</dt><dd className="font-medium">{formatarMoeda(c.valor)} {per[c.periodicidade]}</dd>
            <dt className="text-ink-muted">Início</dt><dd>{formatarData(c.data_inicio)}</dd>
            <dt className="text-ink-muted">Vencimento</dt><dd>dia {c.dia_vencimento}</dd>
            <dt className="text-ink-muted">Próxima renovação</dt><dd>{c.proxima_renovacao ? formatarData(c.proxima_renovacao) : '—'}</dd>
            {c.data_fim && <><dt className="text-ink-muted">Encerrado em</dt><dd>{formatarData(c.data_fim)}</dd></>}
            {c.descontos_pendentes > 0 && <><dt className="text-ink-muted">Desconto na próxima fatura</dt><dd className="text-green-700">{formatarMoeda(c.descontos_pendentes)}</dd></>}
          </dl>
        </Cartao>
      ))}
      <Cartao>
        <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Seus dados</h2>
        <dl className="grid grid-cols-2 gap-y-1 text-sm"><dt className="text-ink-muted">Nome</dt><dd>{r.pessoa.nome}</dd><dt className="text-ink-muted">CPF/CNPJ</dt><dd>{formatarDocumento(r.pessoa.documento)}</dd><dt className="text-ink-muted">Telefone</dt><dd>{formatarTelefone(r.pessoa.telefone) || '—'}</dd><dt className="text-ink-muted">Avisos por WhatsApp</dt><dd>{r.pessoa.receber_avisos ? 'Sim' : 'Não'}</dd></dl>
        <p className="mt-2 text-xs"><Link to="/portal/dados" className="text-brand-700 hover:underline">Atualizar e-mail e telefone</Link></p>
      </Cartao>
    </div>
  )
}

/** Dias úteis (seg–sex) desde uma data — prazo de entrega do presente. */
function diasUteisDesde(inicio: string): number {
  let d = new Date(inicio.slice(0, 10) + 'T12:00:00')
  const hoje = new Date()
  let n = 0
  while (d < hoje) {
    d = new Date(d.getTime() + 86_400_000)
    if (d.getDay() !== 0 && d.getDay() !== 6) n++
  }
  return n
}

/** Vitrine: indicação convertida aguardando a escolha do presente (sem troca depois). */
function EscolhaPresente({ indicacaoId }: { indicacaoId: string }) {
  const opcoes = usePresentesIndicacao(indicacaoId)
  const escolher = useEscolherPresente()
  const [itemId, setItemId] = useState('')
  const selecionado = (opcoes.data ?? []).find((o) => o.item_id === itemId)
  if (opcoes.isPending) return <p className="mt-1 text-xs text-ink-muted">Carregando presentes…</p>
  if ((opcoes.data ?? []).length === 0) return <p className="mt-1 text-xs text-ink-muted">🎁 Seu indicado foi instalado! O provedor vai liberar as opções de presente.</p>
  if (escolher.isSuccess) return <div className="mt-2"><Alerta tipo="sucesso">🎉 Presente confirmado! Entrega em até 10 dias úteis, na sua casa.</Alerta></div>
  return (
    <div className="mt-2 rounded-md border border-line bg-surface/60 p-3">
      <p className="text-sm font-medium">🎁 Parabéns! Toque no presente que você quer (não é possível trocar depois):</p>
      {escolher.error != null && <div className="mt-1"><Alerta tipo="erro">{mensagemDeErro(escolher.error)}</Alerta></div>}
      <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
        {(opcoes.data ?? []).map((o) => (
          <button key={o.item_id} type="button" onClick={() => setItemId(o.item_id)}
            className={`overflow-hidden rounded-lg border text-left transition ${itemId === o.item_id ? 'border-brand-600 ring-2 ring-brand-600' : 'border-line hover:border-brand-600/50'}`}>
            {o.foto
              ? <img src={o.foto} alt={o.nome} className="aspect-square w-full object-cover" />
              : <div className="flex aspect-square w-full items-center justify-center bg-surface text-5xl">🎁</div>}
            <p className="px-2 py-2 text-center text-sm font-medium">{o.nome}</p>
          </button>
        ))}
      </div>
      <div className="mt-3 flex items-center justify-between gap-2">
        <p className="text-xs text-ink-muted">{selecionado ? `Escolhido: ${selecionado.nome}` : 'Toque em um presente para escolher.'}</p>
        <Botao onClick={() => { if (itemId && window.confirm(`Confirmar "${selecionado?.nome}"? Não será possível trocar.`)) escolher.mutate({ indicacaoId, itemId }) }} disabled={!itemId} carregando={escolher.isPending}>Confirmar presente</Botao>
      </div>
      <p className="mt-1 text-xs text-ink-muted">Entrega em até 10 dias úteis, na sua casa.</p>
    </div>
  )
}

export function PortalIndiquePage() {
  const r = usePortal()
  const indicacoes = useIndicacoesCliente()
  const indicar = useIndicar()
  const [negocioId, setNegocioId] = useState(r.negocios[0]?.id ?? '')
  const [nome, setNome] = useState(''); const [telefone, setTelefone] = useState(''); const [erro, setErro] = useState<string | null>(null); const [copiado, setCopiado] = useState(false)
  const cfg = r.negocios.find((n) => n.id === negocioId)?.portal ?? null
  const link = linkIndicacao(r.codigo_indicacao, cfg?.site_url)
  const beneficio = cfg?.beneficio_indicacao ?? 0
  const mesGratis = (cfg?.beneficio_tipo ?? 'mes_gratis') === 'mes_gratis'
  const negocioNome = r.negocios.find((n) => n.id === negocioId)?.nome ?? ''
  const textoConvite = `Olá! Uso a internet da ${negocioNome} e recomendo. Use meu código ${r.codigo_indicacao} ou cadastre-se pelo link: ${link}`
  const whatsapp = `https://wa.me/?text=${encodeURIComponent(textoConvite)}`
  const ganho = useMemo(() => (indicacoes.data ?? []).filter((i) => i.status === 'convertida').reduce((s, i) => s + i.beneficio_valor, 0), [indicacoes.data])
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (nome.trim().length < 2) { setErro('Informe o nome de quem você está indicando.'); return }
    if (somenteDigitos(telefone).length < 10) { setErro('Informe o telefone com DDD.'); return }
    setErro(null)
    indicar.mutate({ negocioId, nome: nome.trim(), telefone: somenteDigitos(telefone) }, { onSuccess: () => { setNome(''); setTelefone('') } })
  }
  async function copiar() { try { await navigator.clipboard.writeText(link); setCopiado(true); setTimeout(() => setCopiado(false), 2000) } catch { /* sem clipboard */ } }
  return (
    <div className="space-y-6">
      <Titulo>Indique e ganhe</Titulo>
      <div className="grid gap-4 sm:grid-cols-3">
        <Indicador rotulo="Indicações" valor={String((indicacoes.data ?? []).length)} />
        <Indicador rotulo="Convertidas" valor={String(r.indicacoes_convertidas)} />
        <Indicador rotulo={mesGratis ? "Meses grátis" : "Desconto conquistado"} valor={mesGratis ? String(r.indicacoes_convertidas) : formatarMoeda(ganho)} />
      </div>
      <Cartao>
        <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Seu link de indicação</h2>
        <p className="text-sm text-ink-muted">{mesGratis ? 'A cada indicação que vira cliente, você ganha 1 mês grátis (100% de desconto na próxima fatura).' : beneficio > 0 ? `A cada indicação que vira cliente, você ganha ${formatarMoeda(beneficio)} de desconto na próxima fatura.` : 'Compartilhe seu link. O provedor define o benefício das indicações.'}</p>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <code className="rounded-md border border-line bg-surface px-3 py-2 text-sm">Código <b>{r.codigo_indicacao}</b> · {link}</code>
          <Botao variante="secundario" onClick={copiar}>{copiado ? 'Copiado!' : 'Copiar link'}</Botao>
          <a href={whatsapp} target="_blank" rel="noreferrer" className="inline-flex h-10 items-center rounded-md bg-green-600 px-4 text-sm font-medium text-white hover:bg-green-700">Convidar pelo WhatsApp</a>
        </div>
      </Cartao>
      <Cartao>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-ink-muted">Indicar alguém agora</h2>
        <form onSubmit={aoEnviar} className="grid gap-3 sm:grid-cols-4" noValidate>
          {(erro || indicar.error) && <div className="sm:col-span-4"><Alerta tipo="erro">{erro ?? mensagemDeErro(indicar.error)}</Alerta></div>}
          {indicar.isSuccess && <div className="sm:col-span-4"><Alerta tipo="sucesso">Indicação registrada. O provedor entra em contato com a pessoa.</Alerta></div>}
          {r.negocios.length > 1 && <Selecao rotulo="Serviço" opcoes={r.negocios.map((n) => ({ valor: n.id, rotulo: n.nome }))} value={negocioId} onChange={(e) => setNegocioId(e.target.value)} />}
          <Campo rotulo="Nome" value={nome} onChange={(e) => setNome(e.target.value)} />
          <Campo rotulo="Telefone (com DDD)" inputMode="tel" value={telefone} onChange={(e) => setTelefone(e.target.value)} />
          <div className="self-end"><Botao type="submit" carregando={indicar.isPending}>Indicar</Botao></div>
        </form>
      </Cartao>
      <Cartao className="p-0">
        <div className="border-b border-line px-4 py-3"><h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Suas indicações</h2></div>
        {indicacoes.isPending ? <div className="p-6"><Carregando /></div> : (indicacoes.data ?? []).length === 0 ? <p className="px-4 py-8 text-center text-sm text-ink-muted">Nenhuma indicação ainda.</p> : (
          <ul className="divide-y divide-line">{(indicacoes.data ?? []).map((i) => (
            <li key={i.id} className="px-4 py-2 text-sm">
              <div className="flex items-center justify-between">
                <span>{i.nome_indicado} <span className="text-xs text-ink-muted">· {formatarData(i.criado_em.slice(0, 10))}</span></span>
                <span className="flex items-center gap-2">{i.status === 'convertida' && i.beneficio_valor > 0 && <span className="text-green-700 tabular-nums">+{formatarMoeda(i.beneficio_valor)}</span>}<Distintivo tom={i.status === 'convertida' ? 'ok' : i.status === 'pendente' ? 'info' : 'neutro'}>{ROTULO_INDICACAO[i.status]}</Distintivo></span>
              </div>
              {i.aguardando_escolha && <EscolhaPresente indicacaoId={i.id} />}
              {i.presente && (
                <div className="mt-1 flex items-center gap-2 text-xs text-ink-muted">
                  {i.presente_foto && <img src={i.presente_foto} alt={i.presente} className="size-10 rounded-md border border-line object-cover" />}
                  <p>
                    🎁 Presente: <span className="font-medium text-ink">{i.presente}</span>
                    {i.presente_entregue_em
                      ? ` — entregue em ${formatarData(i.presente_entregue_em)}`
                      : i.convertida_em
                        ? (diasUteisDesde(i.convertida_em) >= 10 ? ' — entrega para os próximos dias (prazo vencendo)' : ` — entrega em até ${10 - diasUteisDesde(i.convertida_em)} dia(s) útil(eis)`)
                        : ' — entrega em até 10 dias úteis'}
                  </p>
                </div>
              )}
            </li>
          ))}</ul>
        )}
      </Cartao>
    </div>
  )
}

export function PortalPromocoesPage() {
  const promocoes = usePromocoesCliente()
  return (
    <div className="space-y-4">
      <Titulo>Promoções</Titulo>
      {promocoes.isPending ? <Carregando /> : (promocoes.data ?? []).length === 0 ? <Alerta tipo="info">Nenhuma promoção ativa no momento.</Alerta> : (promocoes.data ?? []).map((p) => (
        <Cartao key={p.id}>
          <div className="flex flex-wrap items-start justify-between gap-2"><p className="text-lg font-semibold">{p.titulo}</p><span className="text-xs text-ink-muted">{p.negocio}{p.plano ? ` · plano ${p.plano}` : ''}{p.data_fim ? ` · até ${formatarData(p.data_fim)}` : ''}</span></div>
          <p className="mt-2 whitespace-pre-line text-sm">{p.descricao}</p>
          {p.regras && <p className="mt-2 text-xs text-ink-muted"><span className="font-medium">Regras:</span> {p.regras}</p>}
          {p.como_aderir && <p className="mt-2 rounded-md bg-surface px-3 py-2 text-sm"><span className="font-medium">Como aderir:</span> {p.como_aderir}</p>}
        </Cartao>
      ))}
    </div>
  )
}
