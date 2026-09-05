import { useMemo, useState } from 'react'
import { Link } from 'react-router'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda, hojeISO } from '../../../core/formatos'
import { useContas } from '../../contas/api'
import { useCartoesConfig, useFaturas, useFecharFaturasAgora, useItensFatura, usePagarFatura, useSalvarCartaoConfig } from '../api'
import { ROTULO_STATUS_FATURA, type CartaoConfig, type Fatura } from '../tipos'

const TOM: Record<Fatura['status'], 'ok' | 'alerta' | 'neutro'> = { paga: 'ok', vencida: 'alerta', aberta: 'neutro' }

export function CartoesPage() {
  const contas = useContas()
  const configs = useCartoesConfig()
  const faturas = useFaturas()
  const salvar = useSalvarCartaoConfig()
  const pagar = usePagarFatura()
  const fechar = useFecharFaturasAgora()

  const [configurando, setConfigurando] = useState<{ config?: CartaoConfig } | null>(null)
  const [pagando, setPagando] = useState<Fatura | null>(null)
  const [detalhe, setDetalhe] = useState<Fatura | null>(null)
  const itens = useItensFatura(detalhe?.id ?? null)

  const contasCredito = useMemo(() => (contas.data ?? []).filter((c) => c.tipo === 'credito' && c.ativo), [contas.data])
  const contaPorId = useMemo(() => new Map((contas.data ?? []).map((c) => [c.id, c])), [contas.data])
  const contasPagamento = (contas.data ?? []).filter((c) => c.ativo && c.tipo !== 'credito')
  const semConfig = contasCredito.filter((c) => !(configs.data ?? []).some((k) => k.conta_id === c.id))

  // formulário de configuração
  const [contaId, setContaId] = useState('')
  const [diaFech, setDiaFech] = useState('10')
  const [diaVenc, setDiaVenc] = useState('20')
  const [limite, setLimite] = useState('')
  function abrirConfig(config?: CartaoConfig) {
    setContaId(config?.conta_id ?? semConfig[0]?.id ?? '')
    setDiaFech(String(config?.dia_fechamento ?? 10))
    setDiaVenc(String(config?.dia_vencimento ?? 20))
    setLimite(config ? String(config.limite_total) : '')
    salvar.reset()
    setConfigurando({ config })
  }

  // formulário de pagamento
  const [origemId, setOrigemId] = useState('')
  const [valorPag, setValorPag] = useState('')
  const [dataPag, setDataPag] = useState(hojeISO())
  function abrirPagamento(f: Fatura) {
    setOrigemId(contasPagamento[0]?.id ?? '')
    setValorPag(String(f.valor_total - f.valor_pago))
    setDataPag(hojeISO())
    pagar.reset()
    setPagando(f)
  }

  const carregando = contas.isPending || configs.isPending || faturas.isPending
  const erro = contas.error ?? configs.error ?? faturas.error

  return (
    <>
      <CabecalhoPagina
        titulo="Cartões de crédito"
        descricao="Limite, faturas e pagamento — o cartão é uma conta do tipo crédito"
        acoes={
          <div className="flex gap-2">
            <Botao variante="secundario" onClick={() => fechar.mutate()} carregando={fechar.isPending}>Fechar faturas agora</Botao>
            <Botao onClick={() => abrirConfig()} disabled={semConfig.length === 0 && (configs.data ?? []).length === 0}>Configurar cartão</Botao>
          </div>
        }
      />

      {carregando && <Carregando texto="Carregando cartões…" />}
      {erro && <Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(erro)}</Alerta>}
      {fechar.error && <div className="mb-4"><Alerta tipo="erro">{mensagemDeErro(fechar.error)}</Alerta></div>}

      {!carregando && contasCredito.length === 0 && (
        <Alerta tipo="info" titulo="Nenhuma conta de crédito">
          Crie uma conta do tipo "Cartão de crédito" em <Link to="/contas" className="underline">Contas</Link> com saldo inicial = limite total. Depois configure aqui o fechamento e o vencimento.
        </Alerta>
      )}

      {(configs.data ?? []).length > 0 && (
        <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {(configs.data ?? []).map((k) => {
            const conta = contaPorId.get(k.conta_id)
            const disponivel = Number(conta?.saldo ?? 0)
            return (
              <Cartao key={k.id} className="p-5">
                <div className="flex items-start justify-between">
                  <p className="font-medium">{conta?.nome ?? '—'}</p>
                  <button type="button" className="text-xs font-medium text-brand-600 hover:underline" onClick={() => abrirConfig(k)}>Editar</button>
                </div>
                <p className={`mt-2 text-2xl font-semibold tabular-nums ${disponivel < 0 ? 'text-red-700' : ''}`}>{formatarMoeda(disponivel)}</p>
                <p className="text-xs text-ink-muted">disponível de {formatarMoeda(k.limite_total)} · fecha dia {k.dia_fechamento} · vence dia {k.dia_vencimento}</p>
              </Cartao>
            )
          })}
        </div>
      )}

      {faturas.isSuccess && (
        <Cartao className="p-0">
          <div className="border-b border-line px-6 py-3"><h2 className="text-sm font-semibold">Faturas</h2></div>
          {(faturas.data ?? []).length === 0 ? (
            <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhuma fatura ainda. Compras no cartão entram na próxima fatura, gerada automaticamente no dia do fechamento (ou com "Fechar faturas agora").</p>
          ) : (
            <ul className="divide-y divide-line">
              {(faturas.data ?? []).map((f) => (
                <li key={f.id} className="flex flex-wrap items-center justify-between gap-3 px-6 py-3 text-sm">
                  <button type="button" className="min-w-0 text-left" onClick={() => setDetalhe(f)}>
                    <p className="font-medium">{contaPorId.get(f.conta_id)?.nome ?? '—'} · {formatarData(f.periodo_inicio)} a {formatarData(f.periodo_fim)}</p>
                    <p className="text-xs text-ink-muted">vence {formatarData(f.data_vencimento)}{f.valor_pago > 0 && f.status !== 'paga' ? ` · pago ${formatarMoeda(f.valor_pago)}` : ''}{f.data_pagamento ? ` · pago em ${formatarData(f.data_pagamento)}` : ''}</p>
                  </button>
                  <span className="flex shrink-0 items-center gap-3">
                    <span className="font-medium tabular-nums">{formatarMoeda(f.valor_total)}</span>
                    <Distintivo tom={TOM[f.status]}>{ROTULO_STATUS_FATURA[f.status]}</Distintivo>
                    {f.status !== 'paga' && <Botao variante="secundario" onClick={() => abrirPagamento(f)}>Pagar fatura</Botao>}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Cartao>
      )}

      <Modal aberto={configurando !== null} aoFechar={() => setConfigurando(null)} titulo={configurando?.config ? 'Editar cartão' : 'Configurar cartão'}>
        <div className="space-y-4">
          {salvar.error && <Alerta tipo="erro">{mensagemDeErro(salvar.error)}</Alerta>}
          <Selecao
            rotulo="Conta do cartão (tipo crédito)"
            opcoes={(configurando?.config ? contasCredito : semConfig).map((c) => ({ valor: c.id, rotulo: c.nome }))}
            value={contaId}
            onChange={(e) => setContaId(e.target.value)}
            disabled={Boolean(configurando?.config)}
          />
          <div className="grid grid-cols-3 gap-4">
            <Campo rotulo="Dia do fechamento" type="number" min={1} max={28} value={diaFech} onChange={(e) => setDiaFech(e.target.value)} />
            <Campo rotulo="Dia do vencimento" type="number" min={1} max={28} value={diaVenc} onChange={(e) => setDiaVenc(e.target.value)} />
            <Campo rotulo="Limite total (R$)" type="number" inputMode="decimal" step="0.01" min="0" value={limite} onChange={(e) => setLimite(e.target.value)} />
          </div>
          <p className="text-xs text-ink-muted">O limite disponível é o saldo da conta (saldo inicial = limite total). Compras à vista descontam na hora; parcelas previstas descontam no fechamento da fatura em que caem.</p>
          <div className="flex justify-end gap-2">
            <Botao variante="secundario" onClick={() => setConfigurando(null)}>Cancelar</Botao>
            <Botao
              onClick={() => {
                const f = Number(diaFech); const v = Number(diaVenc); const l = Number(limite.replace(',', '.'))
                if (!contaId || !Number.isInteger(f) || f < 1 || f > 28 || !Number.isInteger(v) || v < 1 || v > 28 || Number.isNaN(l) || l < 0) return
                salvar.mutate({ id: configurando?.config?.id, conta_id: contaId, dia_fechamento: f, dia_vencimento: v, limite_total: Math.round(l * 100) / 100 }, { onSuccess: () => setConfigurando(null) })
              }}
              carregando={salvar.isPending}
            >
              Salvar
            </Botao>
          </div>
        </div>
      </Modal>

      <Modal aberto={pagando !== null} aoFechar={() => setPagando(null)} titulo="Pagar fatura">
        {pagando && (
          <div className="space-y-4">
            {pagar.error && <Alerta tipo="erro">{mensagemDeErro(pagar.error)}</Alerta>}
            <p className="text-sm text-ink-muted">Restante: <span className="font-medium text-ink">{formatarMoeda(pagando.valor_total - pagando.valor_pago)}</span> · vence {formatarData(pagando.data_vencimento)}. O pagamento é uma transferência real e restaura o limite no valor pago.</p>
            <Selecao rotulo="Pagar com a conta" opcoes={contasPagamento.map((c) => ({ valor: c.id, rotulo: `${c.nome} (${formatarMoeda(c.saldo)})` }))} value={origemId} onChange={(e) => setOrigemId(e.target.value)} />
            <div className="grid grid-cols-2 gap-4">
              <Campo rotulo="Valor (R$)" type="number" inputMode="decimal" step="0.01" min="0.01" value={valorPag} onChange={(e) => setValorPag(e.target.value)} />
              <Campo rotulo="Data do pagamento" type="date" value={dataPag} onChange={(e) => setDataPag(e.target.value)} />
            </div>
            <div className="flex justify-end gap-2">
              <Botao variante="secundario" onClick={() => setPagando(null)}>Cancelar</Botao>
              <Botao
                onClick={() => {
                  const v = Number(valorPag.replace(',', '.'))
                  if (!origemId || Number.isNaN(v) || v <= 0) return
                  pagar.mutate({ faturaId: pagando.id, contaOrigemId: origemId, valor: Math.round(v * 100) / 100, data: dataPag }, { onSuccess: () => setPagando(null) })
                }}
                carregando={pagar.isPending}
              >
                Confirmar pagamento
              </Botao>
            </div>
          </div>
        )}
      </Modal>

      <Modal aberto={detalhe !== null} aoFechar={() => setDetalhe(null)} titulo="Detalhe da fatura">
        {detalhe && (
          <div className="space-y-3 text-sm">
            <p className="text-ink-muted">{contaPorId.get(detalhe.conta_id)?.nome ?? '—'} · {formatarData(detalhe.periodo_inicio)} a {formatarData(detalhe.periodo_fim)} · vence {formatarData(detalhe.data_vencimento)}</p>
            {itens.isPending && <Carregando texto="Carregando itens…" />}
            {itens.error && <Alerta tipo="erro">{mensagemDeErro(itens.error)}</Alerta>}
            {itens.isSuccess && (
              <ul className="divide-y divide-line rounded-md border border-line">
                {itens.data.map((l) => (
                  <li key={l.id} className="flex items-center justify-between gap-3 px-4 py-2">
                    <span className="min-w-0">
                      <span className="block truncate font-medium">{l.descricao}</span>
                      <span className="text-xs text-ink-muted">{formatarData(l.data_efetivacao ?? l.data_competencia)}{l.recorrente && l.numero_parcelas ? ` · parcela ${l.parcela_atual} de ${l.numero_parcelas}` : ''}</span>
                    </span>
                    <span className="shrink-0 font-medium tabular-nums text-red-700">− {formatarMoeda(l.valor)}</span>
                  </li>
                ))}
              </ul>
            )}
            <p className="text-right font-semibold tabular-nums">Total: {formatarMoeda(detalhe.valor_total)}{detalhe.valor_pago > 0 ? ` · pago ${formatarMoeda(detalhe.valor_pago)}` : ''}</p>
          </div>
        )}
      </Modal>
    </>
  )
}
