import { useState, type FormEvent } from 'react'
import { Link } from 'react-router'
import { Cartao } from '../../core/ui/Cartao'
import { Alerta } from '../../core/ui/Alerta'
import { Botao } from '../../core/ui/Botao'
import { Campo } from '../../core/ui/Campo'
import { AreaTexto } from '../../core/ui/AreaTexto'
import { Carregando } from '../../core/ui/Carregando'
import { Distintivo } from '../../core/ui/Distintivo'
import { Selecao } from '../../core/ui/Selecao'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../core/formatos'
import { formatarDocumento, formatarTelefone, somenteDigitos } from '../../modules/pessoas/tipos'
import { usePortal } from '../contexto'
import { useAtualizarContato, useContratosCliente, useFaturas, useFidelidade, usePromocoesCliente, useSolicitacoes, useSolicitar, useStatusRede } from '../api'
import { ROTULO_REDE, ROTULO_SITUACAO, ROTULO_STATUS_SOLICITACAO, ROTULO_TIPO_SOLICITACAO, TOM, codigoContrato, linkIndicacao, linkWhatsApp, type EstadoSelo, type Fidelidade, type TipoSolicitacao } from '../tipos'
import { Indicador, Titulo } from './comum'

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']
const mesCurto = (iso: string) => `${MESES[Number(iso.slice(5, 7)) - 1]}/${iso.slice(2, 4)}`
const SELO: Record<EstadoSelo, { classe: string; simbolo: string; rotulo: string }> = {
  ok: { classe: 'bg-brand-600 text-white border-brand-600', simbolo: '✓', rotulo: 'Pago em dia' },
  gratis: { classe: 'bg-brand-600 text-white border-brand-600', simbolo: '★', rotulo: 'Mês grátis' },
  atraso: { classe: 'border-amber-800 text-amber-800', simbolo: '!', rotulo: 'Pago com atraso' },
  vencida: { classe: 'border-red-700 text-red-700', simbolo: '✕', rotulo: 'Vencida' },
  aberto: { classe: 'border-line text-ink-muted', simbolo: '·', rotulo: 'Em aberto' },
  vazio: { classe: 'border-line text-ink-muted opacity-50', simbolo: '', rotulo: 'Ainda não faturado' },
}

function useSuporte() {
  const r = usePortal()
  const cfg = r.negocios.find((n) => n.portal?.whatsapp_suporte)?.portal
  return cfg?.whatsapp_suporte ?? null
}

export function BannerRede() {
  const rede = useStatusRede()
  if (!rede.data?.length) return null
  return <>{rede.data.map((a) => <Alerta key={a.negocio_id} tipo={a.status === 'manutencao' ? 'info' : 'erro'} titulo={a.titulo || ROTULO_REDE[a.status]}>{a.descricao || `${a.negocio}: nossa equipe já está atuando.`} <span className="text-xs opacity-75">Atualizado em {formatarData(a.atualizado_em.slice(0, 10))}</span></Alerta>)}</>
}

export function CartaoFidelidade({ f, compacto }: { f: Fidelidade; compacto?: boolean }) {
  const proximo = f.selos < 6 ? { faltam: 6 - f.selos, premio: '50% de desconto' } : f.selos < 12 ? { faltam: 12 - f.selos, premio: '1 mês grátis' } : null
  return (
    <Cartao>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div><h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Programa Fidelidade</h2><p className="text-sm">{f.plano} <span className="font-mono text-xs text-ink-muted">{codigoContrato(f.codigo)}</span> · ciclo {f.ciclo} ({mesCurto(f.inicio)} a {mesCurto(f.fim)})</p></div>
        <p className="text-lg font-semibold tabular-nums"><span className="text-brand-600">{f.selos}</span><span className="text-sm text-ink-muted">/12 selos</span></p>
      </div>
      <ol className="mt-4 grid grid-cols-6 gap-2 sm:grid-cols-12" aria-label="Selos de fidelidade">
        {f.slots.map((s) => <li key={s.n} title={`${mesCurto(s.competencia)}: ${SELO[s.estado].rotulo}`} className="flex flex-col items-center gap-1"><span className={`flex size-9 items-center justify-center rounded-full border-2 text-sm font-bold ${SELO[s.estado].classe}`}>{SELO[s.estado].simbolo || s.n}</span><span className="text-[10px] text-ink-muted">{mesCurto(s.competencia)}</span></li>)}
      </ol>
      {!compacto && (
        <div className="mt-4 space-y-1 text-sm">
          {f.ativa ? <>
            <p>Pague até o vencimento e ganhe um selo por mês. <b>6 selos</b> = 50% de desconto no mês seguinte. <b>12 selos</b> = 1 mês grátis.</p>
            {proximo ? <p className="text-ink-muted">Faltam <b className="text-ink">{proximo.faltam}</b> selo(s) para {proximo.premio}.</p> : <p className="text-brand-600">Parabéns! Cartão completo: seu mês grátis vem na próxima fatura.</p>}
            {f.premios.map((p) => <p key={p.referencia} className="text-green-700">✓ {p.percentual === 100 ? 'Mês grátis' : '50% de desconto'} garantido em {mesCurto(p.competencia)}.</p>)}
          </> : <p className="text-ink-muted">Programa de fidelidade não ativo para este serviço.</p>}
        </div>
      )}
    </Cartao>
  )
}

export function PortalInicioPage() {
  const r = usePortal()
  const faturas = useFaturas(); const contratos = useContratosCliente(); const fidelidade = useFidelidade(); const promocoes = usePromocoesCliente()
  const suporte = useSuporte()
  const cfg = r.negocios.find((n) => n.portal)?.portal ?? null
  const abertas = (faturas.data ?? []).filter((f) => f.situacao === 'pendente' || f.situacao === 'vencida')
  const proxima = abertas.slice().sort((a, b) => a.data_vencimento.localeCompare(b.data_vencimento))[0]
  const ativos = (contratos.data ?? []).filter((c) => c.status === 'ativo')
  const mesGratis = (cfg?.beneficio_tipo ?? 'mes_gratis') === 'mes_gratis'
  const link = linkIndicacao(r.codigo_indicacao, cfg?.site_url)
  const convite = `Olá! Uso a internet da ${r.negocios[0]?.nome ?? ''} e recomendo. Use meu código ${r.codigo_indicacao} ou cadastre-se pelo link: ${link}`
  return (
    <div className="space-y-6">
      <div><h1 className="text-xl font-semibold">Olá, {r.pessoa.nome.split(' ')[0]}</h1><p className="text-sm text-ink-muted">{formatarDocumento(r.pessoa.documento)}</p></div>
      <BannerRede />
      {suporte && <a href={linkWhatsApp(suporte, `Olá, sou ${r.pessoa.nome} (${formatarDocumento(r.pessoa.documento)}) e preciso de ajuda.`)} target="_blank" rel="noreferrer" className="flex items-center justify-between rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800 hover:opacity-90"><span><b>Suporte pelo WhatsApp</b> · fale com a gente agora</span><span aria-hidden>→</span></a>}
      {r.vencidas > 0 && <Alerta tipo="erro" titulo={`${r.vencidas} fatura(s) vencida(s)`}>Regularize para evitar o bloqueio. <Link to="/portal/faturas" className="underline">Ver faturas</Link>.</Alerta>}
      <div className="grid gap-6 md:grid-cols-2">
        <Cartao>
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Meu plano</h2>
          {contratos.isPending ? <Carregando /> : ativos.length === 0 ? <p className="text-sm text-ink-muted">Nenhum plano ativo.</p> : ativos.map((c) => <div key={c.id} className="py-1"><p className="text-lg font-semibold text-brand-600">{c.plano}</p><p className="text-sm text-ink-muted">{c.plano_descricao ? `${c.plano_descricao} · ` : ''}{formatarMoeda(c.valor)}/mês · vence dia {c.dia_vencimento}</p></div>)}
          <p className="mt-2 text-sm"><Link to="/portal/plano" className="text-brand-700 hover:underline">Detalhes do plano</Link></p>
        </Cartao>
        <Cartao>
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">{proxima?.situacao === 'vencida' ? 'Fatura vencida' : 'Próxima fatura'}</h2>
          {faturas.isPending ? <Carregando /> : !proxima ? <p className="text-sm text-ink-muted">Nenhuma fatura em aberto. Tudo em dia!</p> : (
            <div>
              <p className={`text-2xl font-semibold tabular-nums ${proxima.situacao === 'vencida' ? 'text-red-700' : ''}`}>{formatarMoeda(proxima.valor)}</p>
              <p className="text-sm text-ink-muted">Vencimento {formatarData(proxima.data_vencimento)} · {proxima.plano} <Distintivo tom={TOM[proxima.situacao]}>{ROTULO_SITUACAO[proxima.situacao]}</Distintivo></p>
              {proxima.observacao && <p className="mt-1 text-xs text-green-700">{proxima.observacao}</p>}
              {proxima.chave_pix && <p className="mt-2 text-sm">Pix: <span className="font-mono">{proxima.chave_pix}</span></p>}
              {abertas.length > 1 && <p className="mt-1 text-xs text-ink-muted">Você tem {abertas.length} faturas em aberto (total {formatarMoeda(r.em_aberto)}).</p>}
              <p className="mt-2 text-sm"><Link to={`/portal/faturas/${proxima.id}`} className="text-brand-700 hover:underline">Ver fatura / PDF</Link> · <Link to="/portal/faturas" className="text-brand-700 hover:underline">Todas</Link></p>
            </div>
          )}
        </Cartao>
      </div>
      {fidelidade.data?.[0] && <CartaoFidelidade f={fidelidade.data[0]} compacto />}
      {(promocoes.data ?? []).length > 0 && (
        <Cartao>
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Promoções e benefícios</h2>
          <ul className="space-y-1 text-sm">{(promocoes.data ?? []).slice(0, 3).map((p) => <li key={p.id}><b>{p.titulo}</b> · {p.descricao}</li>)}</ul>
          <p className="mt-2 text-sm"><Link to="/portal/promocoes" className="text-brand-700 hover:underline">Ver todas</Link></p>
        </Cartao>
      )}
      <Cartao>
        <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-muted">Indique e ganhe</h2>
        <p className="text-sm">{mesGratis ? 'Cada amigo que virar cliente = 1 mês grátis para você.' : `Cada amigo que virar cliente = ${formatarMoeda(cfg?.beneficio_indicacao ?? 0)} de desconto para você.`} Seu código: <b className="font-mono text-brand-600">{r.codigo_indicacao}</b></p>
        <div className="mt-3 flex flex-wrap gap-2">
          <a href={`https://wa.me/?text=${encodeURIComponent(convite)}`} target="_blank" rel="noreferrer" className="inline-flex h-10 items-center rounded-md bg-green-600 px-4 text-sm font-medium text-white hover:bg-green-700">Enviar pelo WhatsApp</a>
          <Link to="/portal/indique"><Botao variante="secundario">Minhas indicações</Botao></Link>
        </div>
      </Cartao>
      <div className="grid gap-4 sm:grid-cols-3">
        <Indicador rotulo="Em aberto" valor={formatarMoeda(r.em_aberto)} tom={r.vencidas > 0 ? 'alerta' : undefined} />
        <Link to="/portal/dados"><Indicador rotulo="Meus dados" valor={formatarTelefone(r.pessoa.telefone) || 'Atualizar'} /></Link>
        <Link to="/portal/chamados"><Indicador rotulo="Precisa de ajuda?" valor="Abrir chamado" /></Link>
      </div>
    </div>
  )
}

export function PortalFidelidadePage() {
  const fidelidade = useFidelidade()
  return (
    <div className="space-y-4">
      <Titulo>Programa Fidelidade</Titulo>
      {fidelidade.isPending ? <Carregando /> : fidelidade.isError ? <Alerta tipo="erro">{mensagemDeErro(fidelidade.error)}</Alerta> : (fidelidade.data ?? []).length === 0 ? <Alerta tipo="info">Nenhum plano mensal ativo.</Alerta> : (fidelidade.data ?? []).map((f) => <CartaoFidelidade key={f.contrato_id} f={f} />)}
    </div>
  )
}

export function PortalChamadosPage() {
  const r = usePortal()
  const solicitacoes = useSolicitacoes(); const solicitar = useSolicitar(); const contratos = useContratosCliente()
  const suporte = useSuporte()
  const [negocioId, setNegocioId] = useState(r.negocios[0]?.id ?? ''); const [tipo, setTipo] = useState<TipoSolicitacao>('suporte'); const [descricao, setDescricao] = useState(''); const [erro, setErro] = useState<string | null>(null); const [protocolo, setProtocolo] = useState<string | null>(null)
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (descricao.trim().length < 5) { setErro('Descreva o que está acontecendo (mínimo 5 caracteres).'); return }
    setErro(null)
    const contrato = (contratos.data ?? []).find((c) => c.status === 'ativo')
    solicitar.mutate({ negocioId, tipo, descricao: descricao.trim(), contratoId: contrato?.id ?? null }, { onSuccess: (s) => { setProtocolo(s.protocolo); setDescricao('') } })
  }
  const textoZap = protocolo ? `Olá! Abri o chamado ${protocolo} pelo portal: ${ROTULO_TIPO_SOLICITACAO[tipo]}.` : ''
  return (
    <div className="space-y-6">
      <Titulo>Chamados</Titulo>
      <Cartao>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-ink-muted">Abrir chamado</h2>
        <form onSubmit={aoEnviar} className="space-y-3" noValidate>
          {(erro || solicitar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(solicitar.error)}</Alerta>}
          {protocolo && <Alerta tipo="sucesso" titulo={`Protocolo ${protocolo}`}>Chamado registrado. Acompanhe abaixo.{suporte && <> <a href={linkWhatsApp(suporte, textoZap)} target="_blank" rel="noreferrer" className="underline">Falar no WhatsApp</a></>}</Alerta>}
          <div className="grid gap-3 sm:grid-cols-2">
            {r.negocios.length > 1 && <Selecao rotulo="Serviço" opcoes={r.negocios.map((n) => ({ valor: n.id, rotulo: n.nome }))} value={negocioId} onChange={(e) => setNegocioId(e.target.value)} />}
            <Selecao rotulo="Tipo" opcoes={(Object.keys(ROTULO_TIPO_SOLICITACAO) as TipoSolicitacao[]).map((t) => ({ valor: t, rotulo: ROTULO_TIPO_SOLICITACAO[t] }))} value={tipo} onChange={(e) => setTipo(e.target.value as TipoSolicitacao)} />
          </div>
          <AreaTexto rotulo="Descrição" rows={3} maxLength={1000} value={descricao} onChange={(e) => setDescricao(e.target.value)} placeholder="Ex.: internet caiu hoje às 14h, luz vermelha no modem" />
          <div className="flex justify-end"><Botao type="submit" carregando={solicitar.isPending}>Enviar chamado</Botao></div>
        </form>
      </Cartao>
      <Cartao className="p-0">
        <div className="border-b border-line px-4 py-3"><h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Meus chamados</h2></div>
        {solicitacoes.isPending ? <div className="p-6"><Carregando /></div> : (solicitacoes.data ?? []).length === 0 ? <p className="px-4 py-8 text-center text-sm text-ink-muted">Nenhum chamado aberto.</p> : (
          <ul className="divide-y divide-line">{(solicitacoes.data ?? []).map((s) => <li key={s.id} className="px-4 py-3 text-sm"><div className="flex items-center justify-between gap-2"><span><span className="font-mono text-xs text-ink-muted">{s.protocolo}</span> · {ROTULO_TIPO_SOLICITACAO[s.tipo]}</span><Distintivo tom={s.status === 'concluida' ? 'ok' : s.status === 'em_andamento' ? 'info' : 'neutro'}>{ROTULO_STATUS_SOLICITACAO[s.status]}</Distintivo></div>{s.descricao && <p className="mt-1 text-ink-muted">{s.descricao}</p>}{s.resposta && <p className="mt-1 rounded-md bg-surface px-3 py-2"><b>Resposta:</b> {s.resposta}</p>}<p className="mt-1 text-xs text-ink-muted">{formatarData(s.criado_em.slice(0, 10))}</p></li>)}</ul>
        )}
      </Cartao>
    </div>
  )
}

export function PortalDadosPage() {
  const r = usePortal()
  const atualizar = useAtualizarContato()
  const [email, setEmail] = useState(r.pessoa.email ?? ''); const [telefone, setTelefone] = useState(formatarTelefone(r.pessoa.telefone) || ''); const [avisos, setAvisos] = useState(r.pessoa.receber_avisos); const [erro, setErro] = useState<string | null>(null)
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const tel = somenteDigitos(telefone)
    if (tel.length < 10 || tel.length > 13) { setErro('Informe o telefone com DDD.'); return }
    if (email.trim() && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) { setErro('E-mail inválido.'); return }
    setErro(null)
    atualizar.mutate({ email: email.trim().toLowerCase(), telefone: tel, receberAvisos: avisos })
  }
  return (
    <div className="space-y-4">
      <Titulo>Meus dados</Titulo>
      <Cartao>
        <dl className="grid grid-cols-2 gap-y-1 text-sm"><dt className="text-ink-muted">Nome</dt><dd>{r.pessoa.nome}</dd><dt className="text-ink-muted">CPF/CNPJ</dt><dd>{formatarDocumento(r.pessoa.documento)}</dd></dl>
        <p className="mt-1 text-xs text-ink-muted">Nome e documento só mudam com o provedor.</p>
      </Cartao>
      <Cartao>
        <form onSubmit={aoEnviar} className="space-y-4" noValidate>
          {(erro || atualizar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(atualizar.error)}</Alerta>}
          {atualizar.isSuccess && <Alerta tipo="sucesso">Dados atualizados.</Alerta>}
          <div className="grid gap-4 sm:grid-cols-2">
            <Campo rotulo="E-mail" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
            <Campo rotulo="WhatsApp / telefone (com DDD)" inputMode="tel" value={telefone} onChange={(e) => setTelefone(e.target.value)} />
          </div>
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={avisos} onChange={(e) => setAvisos(e.target.checked)} className="size-4 accent-brand-600" />Receber lembretes de fatura pelo WhatsApp</label>
          <div className="flex justify-end"><Botao type="submit" carregando={atualizar.isPending}>Salvar</Botao></div>
        </form>
      </Cartao>
    </div>
  )
}
