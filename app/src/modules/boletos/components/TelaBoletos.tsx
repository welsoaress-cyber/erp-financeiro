import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { BarraFiltros, ContagemFiltro } from '../../../core/ui/Filtros'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../../core/formatos'
import { formatarTelefone } from '../../pessoas/tipos'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { useConcederDesconto, useDefinirCodigoBarras } from '../../lancamentos/api'
import { useBoletosPendentes, useRegistrarBoletoEnviado } from '../api'
import type { BoletoPendente } from '../tipos'

const linkWhatsApp = (numero: string, texto: string) => `https://wa.me/${numero.replace(/\D/g, '')}?text=${encodeURIComponent(texto)}`

function mensagemPadrao(b: BoletoPendente): string {
  const linhas = [
    `Olá, ${b.pessoa.split(' ')[0]}! Segue o boleto referente a "${b.descricao}", vencimento em ${formatarData(b.data_vencimento)}, valor ${formatarMoeda(b.valor)}.`,
  ]
  if (b.codigo_barras) linhas.push(`Código de barras: ${b.codigo_barras}`)
  if (b.valor_desconto > 0) linhas.push(`(Desconto de ${formatarMoeda(b.valor_desconto)} já aplicado — ${b.motivo_desconto})`)
  return linhas.join('\n')
}

/** Linha de um boleto pendente: WhatsApp, código de barras e desconto inline, marcar como enviado. */
function LinhaBoleto({ b }: { b: BoletoPendente }) {
  const qc = useQueryClient()
  const { organizacao } = useOrganizacao()
  const invalidarPendentes = () => void qc.invalidateQueries({ queryKey: ['boletos-pendentes', organizacao.id] })
  const registrar = useRegistrarBoletoEnviado()
  const concederDesconto = useConcederDesconto()
  const definirCodigo = useDefinirCodigoBarras()
  const [editandoCodigo, setEditandoCodigo] = useState(false)
  const [codigo, setCodigo] = useState(b.codigo_barras ?? '')
  const [editandoDesconto, setEditandoDesconto] = useState(false)
  const [desconto, setDesconto] = useState(b.valor_desconto > 0 ? String(b.valor_desconto) : '')
  const [motivoDesconto, setMotivoDesconto] = useState(b.motivo_desconto ?? '')

  function salvarCodigo() {
    definirCodigo.mutate({ id: b.id, codigo: codigo.trim() || null }, { onSuccess: () => { setEditandoCodigo(false); invalidarPendentes() } })
  }
  function salvarDesconto() {
    const v = Number(desconto.replace(',', '.')) || 0
    concederDesconto.mutate({ id: b.id, valor_desconto: Math.round(v * 100) / 100, motivo: motivoDesconto.trim() || null }, {
      onSuccess: () => { setEditandoDesconto(false); invalidarPendentes() },
    })
  }
  function marcarEnviado() {
    registrar.mutate({ lancamento_id: b.id, mensagem: mensagemPadrao(b) })
  }

  return (
    <li className="px-6 py-3 text-sm">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="min-w-0">
          <span className="font-medium">{b.pessoa}</span>
          <span className="ml-2 text-xs text-ink-muted">
            {b.telefone ? formatarTelefone(b.telefone) : 'sem telefone'} · vence dia {b.dia_vencimento} ({formatarData(b.data_vencimento)}) · {b.negocio} · contrato #{String(b.contrato_codigo).padStart(3, '0')}
          </span>
        </span>
        <span className="flex shrink-0 items-center gap-3">
          <span className="tabular-nums">
            {b.valor_desconto > 0 && <span className="mr-1 text-xs text-ink-muted line-through">{formatarMoeda(b.valor + b.valor_desconto)}</span>}
            <span className="font-medium">{formatarMoeda(b.valor)}</span>
          </span>
          <button type="button" className="text-xs font-medium text-brand-600 hover:underline" onClick={() => setEditandoDesconto((v) => !v)}>
            {b.valor_desconto > 0 ? 'Desconto' : '+ Desconto'}
          </button>
          <button type="button" className="text-xs font-medium text-brand-600 hover:underline" onClick={() => setEditandoCodigo((v) => !v)}>
            {b.codigo_barras ? 'Código' : '+ Código'}
          </button>
          {b.telefone && (
            <a href={linkWhatsApp(b.telefone, mensagemPadrao(b))} target="_blank" rel="noreferrer"
              className="inline-flex h-9 items-center rounded-md bg-green-600 px-3 text-sm font-medium text-white hover:bg-green-700">
              WhatsApp
            </a>
          )}
          <Botao type="button" variante="secundario" carregando={registrar.isPending} onClick={marcarEnviado}>Marcar como enviado</Botao>
        </span>
      </div>
      {editandoCodigo && (
        <div className="mt-2 flex flex-wrap items-end gap-2 rounded-md bg-canvas p-3">
          {definirCodigo.error && <div className="w-full"><Alerta tipo="erro">{mensagemDeErro(definirCodigo.error)}</Alerta></div>}
          <div className="min-w-64 flex-1"><Campo rotulo="Código de barras / linha digitável" value={codigo} onChange={(e) => setCodigo(e.target.value)} /></div>
          <Botao type="button" variante="secundario" onClick={() => setEditandoCodigo(false)}>Cancelar</Botao>
          <Botao type="button" carregando={definirCodigo.isPending} onClick={salvarCodigo}>Salvar</Botao>
        </div>
      )}
      {editandoDesconto && (
        <div className="mt-2 flex flex-wrap items-end gap-2 rounded-md bg-canvas p-3">
          {concederDesconto.error && <div className="w-full"><Alerta tipo="erro">{mensagemDeErro(concederDesconto.error)}</Alerta></div>}
          <Campo rotulo="Desconto (R$)" type="number" inputMode="decimal" step="0.01" min="0" value={desconto} onChange={(e) => setDesconto(e.target.value)} />
          <div className="min-w-48 flex-1"><Campo rotulo="Motivo" value={motivoDesconto} onChange={(e) => setMotivoDesconto(e.target.value)} placeholder="Negociação, pontualidade…" /></div>
          <Botao type="button" variante="secundario" onClick={() => setEditandoDesconto(false)}>Cancelar</Botao>
          <Botao type="button" carregando={concederDesconto.isPending} onClick={salvarDesconto}>Salvar</Botao>
        </div>
      )}
    </li>
  )
}

/** Controle de Boletos (0126): quem é boleto, previsto, sem registro de envio — filtrado por negócio e por dia de vencimento. */
export function TelaBoletos({ negocioId }: { negocioId: string }) {
  const pendentes = useBoletosPendentes()
  const [diaDe, setDiaDe] = useState('')
  const [diaAte, setDiaAte] = useState('')

  const doNegocio = (pendentes.data ?? []).filter((b) => b.negocio_id === negocioId)
  const de = Number(diaDe) || 1
  const ate = Number(diaAte) || 31
  const filtrados = doNegocio.filter((b) => b.dia_vencimento >= de && b.dia_vencimento <= ate)

  return (
    <div className="rounded-lg border border-line bg-white">
      <div className="border-b border-line px-6 py-3">
        <h2 className="text-sm font-semibold">Boletos pendentes de envio</h2>
        <p className="text-xs text-ink-muted">Clientes com forma de pagamento boleto, fatura prevista, ainda sem registro de envio. Bloqueados e pagos já saem sozinhos da lista.</p>
      </div>
      <BarraFiltros>
        <label className="flex items-center gap-1 text-xs text-ink-muted">Dia de vencimento, de
          <input type="number" min={1} max={31} value={diaDe} onChange={(e) => setDiaDe(e.target.value)} placeholder="1" className="h-9 w-16 rounded-md border border-line bg-white px-2 text-center text-sm text-ink" />
          até
          <input type="number" min={1} max={31} value={diaAte} onChange={(e) => setDiaAte(e.target.value)} placeholder="31" className="h-9 w-16 rounded-md border border-line bg-white px-2 text-center text-sm text-ink" />
        </label>
        <ContagemFiltro visiveis={filtrados.length} total={doNegocio.length} singular="boleto" plural="boletos" />
      </BarraFiltros>
      {pendentes.isPending ? <div className="p-6"><Carregando /></div> : pendentes.error ? (
        <div className="p-6"><Alerta tipo="erro">{mensagemDeErro(pendentes.error)}</Alerta></div>
      ) : filtrados.length === 0 ? (
        <p className="px-6 py-10 text-center text-sm text-ink-muted">{doNegocio.length === 0 ? 'Nenhum boleto pendente de envio. 👍' : 'Nenhum boleto nessa faixa de vencimento.'}</p>
      ) : (
        <ul className="divide-y divide-line">
          {filtrados.map((b) => <LinhaBoleto key={b.id} b={b} />)}
        </ul>
      )}
    </div>
  )
}
