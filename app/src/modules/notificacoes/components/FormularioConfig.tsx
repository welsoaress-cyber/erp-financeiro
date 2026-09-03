import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { useSalvarConfig } from '../api'
import { PLACEHOLDERS, TEMPLATES_PADRAO, renderizar, type ConfigNotificacao } from '../tipos'

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
  const [diasAntes, setDiasAntes] = useState(String(config?.dias_antes ?? 3))
  const [diasApos, setDiasApos] = useState(String(config?.dias_apos ?? 3))
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
    const dA = Number(diasAntes), dP = Number(diasApos)
    if (!Number.isInteger(dA) || dA < 0 || dA > 30) { setErro('Dias antes: 0 a 30.'); return }
    if (!Number.isInteger(dP) || dP < 1 || dP > 60) { setErro('Dias após: 1 a 60.'); return }
    if (horaFim <= horaInicio) { setErro('O fim do horário comercial deve ser depois do início.'); return }
    for (const t of [tplProximo, tplDia, tplBloqueio]) if (t.trim().length < 10 || t.length > 1000) { setErro('Cada mensagem precisa ter entre 10 e 1000 caracteres.'); return }
    setErro(null)
    salvar.mutate({ id: config?.id, negocioId, dados: { numero_whatsapp: num || null, ativo, dias_antes: dA, dias_apos: dP, hora_inicio: horaInicio, hora_fim: horaFim, template_vencimento_proximo: tplProximo.trim(), template_vencimento_dia: tplDia.trim(), template_bloqueio: tplBloqueio.trim() } }, { onSuccess: aoConcluir })
  }

  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || salvar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(salvar.error)}</Alerta>}
      <Alerta tipo="info">Modo simulado: nenhuma mensagem sai do sistema. Os avisos ficam registrados no histórico como "Simulado" até a integração real ser autorizada.</Alerta>
      <div className="grid gap-4 sm:grid-cols-2">
        <Campo rotulo="Número de WhatsApp do negócio" value={numero} onChange={(e) => setNumero(e.target.value)} placeholder="+5511954490001" />
        <label className="flex items-center gap-2 self-end pb-2 text-sm font-medium"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />Notificações ativas</label>
      </div>
      <div className="grid gap-4 sm:grid-cols-4">
        <Campo rotulo="Dias antes do vencimento" type="number" min={0} max={30} value={diasAntes} onChange={(e) => setDiasAntes(e.target.value)} />
        <Campo rotulo="Dias após (bloqueio)" type="number" min={1} max={60} value={diasApos} onChange={(e) => setDiasApos(e.target.value)} />
        <Campo rotulo="Horário comercial: início" type="time" value={horaInicio} onChange={(e) => setHoraInicio(e.target.value)} />
        <Campo rotulo="Horário comercial: fim" type="time" value={horaFim} onChange={(e) => setHoraFim(e.target.value)} />
      </div>
      <p className="text-xs text-ink-muted">Variáveis: {PLACEHOLDERS.join(' ')}. Fora do horário comercial (Brasília) os avisos ficam pendentes até a próxima execução.</p>
      <Template rotulo="Mensagem: próximo ao vencimento" valor={tplProximo} aoMudar={setTplProximo} exemplo={exemplo} />
      <Template rotulo="Mensagem: no dia do vencimento" valor={tplDia} aoMudar={setTplDia} exemplo={exemplo} />
      <Template rotulo="Mensagem: bloqueio (após vencimento sem pagamento)" valor={tplBloqueio} aoMudar={setTplBloqueio} exemplo={exemplo} />
      <div className="flex justify-end gap-2"><Botao type="submit" carregando={salvar.isPending}>Salvar configuração</Botao></div>
    </form>
  )
}
