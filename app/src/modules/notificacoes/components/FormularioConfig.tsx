import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { useSalvarConfig } from '../api'
import { PLACEHOLDERS, PROVEDORES, TEMPLATES_PADRAO, renderizar, type ConfigNotificacao, type ProvedorNotificacao } from '../tipos'

function Template({ rotulo, valor, aoMudar, exemplo }: { rotulo: string; valor: string; aoMudar: (v: string) => void; exemplo: Record<string, string> }) {
  return (
    <div className="space-y-1">
      <AreaTexto rotulo={rotulo} rows={3} maxLength={1000} value={valor} onChange={(e) => aoMudar(e.target.value)} />
      <p className="rounded-md bg-surface px-3 py-2 text-xs text-ink-muted"><span className="font-medium">Prévia:</span> {renderizar(valor, exemplo)}</p>
    </div>
  )
}

const EXEMPLO = { nome: 'Maria Souza', negocio: 'SERVNET', plano: 'Fibra 500', valor: 'R$ 99,90', vencimento: '10/10/2026', contrato: '#012', dias: '3' }

export function FormularioConfig({ negocioId, negocioNome, config, aoConcluir }: { negocioId: string; negocioNome: string; config: ConfigNotificacao | null; aoConcluir: () => void }) {
  const salvar = useSalvarConfig()
  const [numero, setNumero] = useState(config?.numero_whatsapp ?? '')
  const [ativo, setAtivo] = useState(config?.ativo ?? false)
  const [provedor, setProvedor] = useState<ProvedorNotificacao>(config?.provedor ?? 'simulado')
  const [instancia, setInstancia] = useState(config?.instancia ?? '')
  const [reguaAntes, setReguaAntes] = useState((config?.regua_antes ?? [2]).join(', '))
  const [reguaApos, setReguaApos] = useState((config?.regua_apos ?? [3]).join(', '))
  const [horaInicio, setHoraInicio] = useState((config?.hora_inicio ?? '08:00').slice(0, 5))
  const [horaFim, setHoraFim] = useState((config?.hora_fim ?? '18:00').slice(0, 5))
  const [tplProximo, setTplProximo] = useState(config?.template_vencimento_proximo ?? TEMPLATES_PADRAO.template_vencimento_proximo)
  const [tplDia, setTplDia] = useState(config?.template_vencimento_dia ?? TEMPLATES_PADRAO.template_vencimento_dia)
  const [tplBloqueio, setTplBloqueio] = useState(config?.template_bloqueio ?? TEMPLATES_PADRAO.template_bloqueio)
  const [erro, setErro] = useState<string | null>(null)
  const exemplo = { ...EXEMPLO, negocio: negocioNome }

  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const num = numero.replace(/[^0-9+]/g, '')
    if (ativo && !num) { setErro('Informe o número de WhatsApp do negócio para ativar.'); return }
    if (num && !/^\+[1-9][0-9]{9,14}$/.test(num)) { setErro('Número no formato internacional, ex.: +5511954490001.'); return }
    const lerRegua = (texto: string) => texto.split(/[,;\s]+/).filter(Boolean).map(Number)
    const rA = lerRegua(reguaAntes), rP = lerRegua(reguaApos)
    if (rA.some((d) => !Number.isInteger(d) || d < 1 || d > 30) || rA.length > 5) { setErro('Avisos antes: até 5 números de 1 a 30 (ex.: 2 ou 5, 2). Vazio = nenhum.'); return }
    if (rP.some((d) => !Number.isInteger(d) || d < 1 || d > 60) || rP.length > 5) { setErro('Avisos depois: até 5 números de 1 a 60 (ex.: 3 ou 1, 3).'); return }
    if (horaFim <= horaInicio) { setErro('O fim do horário comercial deve ser depois do início.'); return }
    const inst = instancia.trim().toLowerCase()
    if (provedor === 'evolution' && !/^[a-z0-9_-]{2,40}$/.test(inst)) { setErro('Informe o nome da instância da Evolution API (ex.: servnet).'); return }
    for (const t of [tplProximo, tplDia, tplBloqueio]) if (t.trim().length < 10 || t.length > 1000) { setErro('Cada mensagem precisa ter entre 10 e 1000 caracteres.'); return }
    setErro(null)
    salvar.mutate({ id: config?.id, negocioId, dados: { numero_whatsapp: num || null, provedor, instancia: provedor === 'evolution' ? inst : null, ativo, regua_antes: rA, regua_apos: rP, hora_inicio: horaInicio, hora_fim: horaFim, template_vencimento_proximo: tplProximo.trim(), template_vencimento_dia: tplDia.trim(), template_bloqueio: tplBloqueio.trim() } }, { onSuccess: aoConcluir })
  }

  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || salvar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(salvar.error)}</Alerta>}
      {provedor === 'simulado'
        ? <Alerta tipo="info">Modo simulado: nenhuma mensagem sai do sistema. Os avisos ficam registrados no histórico como "Simulado".</Alerta>
        : <Alerta tipo="info" titulo="Envio real pela Evolution API">As mensagens pendentes são enviadas pela instância informada uma vez ao dia (09:05, Brasília) ou pelo botão "Enviar pendentes agora". Requer os secrets EVOLUTION_API_URL, EVOLUTION_API_KEY e NOTIFICACOES_CRON_SECRET configurados no painel do Supabase (nunca no código).</Alerta>}
      <div className="grid gap-4 sm:grid-cols-2">
        <Selecao rotulo="Provedor de envio" opcoes={PROVEDORES} value={provedor} onChange={(e) => setProvedor(e.target.value as ProvedorNotificacao)} />
        {provedor === 'evolution' && <Campo rotulo="Instância na Evolution API" value={instancia} onChange={(e) => setInstancia(e.target.value)} placeholder="servnet" />}
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <Campo rotulo="Número de WhatsApp do negócio" value={numero} onChange={(e) => setNumero(e.target.value)} placeholder="+5511954490001" />
        <label className="flex items-center gap-2 self-end pb-2 text-sm font-medium"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />Notificações ativas</label>
      </div>
      <div className="grid gap-4 sm:grid-cols-4">
        <Campo rotulo="Avisar antes (dias)" value={reguaAntes} onChange={(e) => setReguaAntes(e.target.value)} placeholder="2 ou 5, 2" title="Um aviso em cada dia listado antes do vencimento. Vazio = nenhum aviso antes." />
        <Campo rotulo="Avisar depois (dias)" value={reguaApos} onChange={(e) => setReguaApos(e.target.value)} placeholder="3 ou 1, 3" title="Um aviso de bloqueio em cada dia listado após o vencimento. O maior é o prazo do bloqueio assistido." />
        <Campo rotulo="Horário comercial: início" type="time" value={horaInicio} onChange={(e) => setHoraInicio(e.target.value)} />
        <Campo rotulo="Horário comercial: fim" type="time" value={horaFim} onChange={(e) => setHoraFim(e.target.value)} />
      </div>
      <p className="text-xs text-ink-muted">Régua padrão enxuta: 2 dias antes · no dia · 3 dias depois (o aviso do dia sempre sai). Cada ponto manda no máximo uma mensagem por fatura. Variáveis: {PLACEHOLDERS.join(' ')}. Fora do horário comercial (Brasília) os avisos ficam pendentes até a próxima execução.</p>
      <Template rotulo="Mensagem: próximo ao vencimento" valor={tplProximo} aoMudar={setTplProximo} exemplo={exemplo} />
      <Template rotulo="Mensagem: no dia do vencimento" valor={tplDia} aoMudar={setTplDia} exemplo={exemplo} />
      <Template rotulo="Mensagem: bloqueio (após vencimento sem pagamento)" valor={tplBloqueio} aoMudar={setTplBloqueio} exemplo={exemplo} />
      <div className="flex justify-end gap-2"><Botao type="submit" carregando={salvar.isPending}>Salvar configuração</Botao></div>
    </form>
  )
}
