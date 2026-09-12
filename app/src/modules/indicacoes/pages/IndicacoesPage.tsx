import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { formatarTelefone } from '../../pessoas/tipos'
import { useCancelarIndicacao, useConverterIndicacao, useCriarIndicacaoAdmin, useEntregarPresente, useEscolherPresenteAdmin, useIndicacoesAdmin, usePortalConfigs, usePremiosAdmin } from '../../portal/api'
import { useEstoqueItens } from '../../estoque/api'
import { useContratos } from '../../contratos/api'
import type { IndicacaoAdmin } from '../../portal/tipos'
import { VitrinePremiosAdmin } from '../../portal/components/VitrinePremiosAdmin'

type Janela = { tipo: 'converter'; indicacao: IndicacaoAdmin } | { tipo: 'nova-indicacao' } | null

/** Dias úteis (seg–sex) entre duas datas — prazo de entrega do presente. */
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

/** Central do Indique e Ganhe: métricas, indicações (converter/escolher/entregar) e vitrine de prêmios. */
export function IndicacoesPage() {
  const negocios = useNegocios(); const configs = usePortalConfigs(); const indicacoes = useIndicacoesAdmin(); const pessoas = usePessoas()
  const converter = useConverterIndicacao(); const cancelar = useCancelarIndicacao()
  const criarInd = useCriarIndicacaoAdmin(); const escolherPresente = useEscolherPresenteAdmin(); const entregar = useEntregarPresente()
  const itensEstoque = useEstoqueItens(); const contratos = useContratos(); const premios = usePremiosAdmin()
  const [negocioSel, setNegocioSel] = useState(''); const [janela, setJanela] = useState<Janela>(null); const [pessoaConv, setPessoaConv] = useState('')
  const [novoIndicante, setNovoIndicante] = useState(''); const [novoNome, setNovoNome] = useState(''); const [novoTel, setNovoTel] = useState('')
  const [presenteSel, setPresenteSel] = useState<Record<string, string>>({})
  const ativos = useMemo(() => (negocios.data ?? []).filter((n) => n.ativo), [negocios.data])
  const negocio = ativos.find((n) => n.id === negocioSel) ?? ativos[0] ?? null
  const config = (configs.data ?? []).find((c) => c.negocio_id === negocio?.id) ?? null
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const inds = (indicacoes.data ?? []).filter((i) => i.negocio_id === negocio?.id)
  const nomeItem = useMemo(() => new Map((itensEstoque.data ?? []).map((i) => [i.id, i.nome])), [itensEstoque.data])
  const brindes = useMemo(() => {
    const itensPremio = new Set((premios.data ?? []).filter((p) => p.negocio_id === negocio?.id && p.ativo).map((p) => p.item_id))
    return (itensEstoque.data ?? []).filter((i) => i.negocio_id === negocio?.id && i.ativo && itensPremio.has(i.id))
  }, [itensEstoque.data, premios.data, negocio?.id])
  const convertidas = inds.filter((i) => i.status === 'convertida')
  const custoPresentes = convertidas.reduce((s, i) => s + (i.presente_custo ?? 0), 0)
  const mrrGerado = convertidas.reduce((s, i) => {
    const c = (contratos.data ?? []).find((x) => x.pessoa_id === i.indicado_pessoa_id && x.negocio_id === i.negocio_id && x.status === 'ativo')
    return s + (c ? Number(c.valor) : 0)
  }, 0)
  const fechar = () => { setJanela(null); setPessoaConv(''); setNovoIndicante(''); setNovoNome(''); setNovoTel(''); criarInd.reset() }
  if (negocios.isPending || indicacoes.isPending) return <><CabecalhoPagina titulo="Indicações" /><Carregando /></>
  return (
    <>
      <CabecalhoPagina titulo="Indicações" descricao="Campanha Indique e Ganhe: indicações, presentes e vitrine"
        acoes={negocio ? (
          <span className="flex items-center gap-2">
            {ativos.length > 1 && <select aria-label="Negócio" value={negocio.id} onChange={(e) => setNegocioSel(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">{ativos.map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}</select>}
            <Botao onClick={() => setJanela({ tipo: 'nova-indicacao' })}>Nova indicação</Botao>
          </span>
        ) : undefined} />
      {!negocio && <Alerta tipo="info">Cadastre um negócio ativo antes.</Alerta>}
      {negocio && (
        <div className="space-y-6">
          <Cartao className="p-0">
            <div className="grid grid-cols-2 gap-4 border-b border-line px-6 py-3 text-sm sm:grid-cols-5">
              <div><p className="text-xs uppercase text-ink-muted">Indicações</p><p className="font-semibold tabular-nums">{inds.filter((i) => i.status !== 'cancelada').length}</p></div>
              <div><p className="text-xs uppercase text-ink-muted">Convertidas</p><p className="font-semibold tabular-nums">{convertidas.length}{inds.length > 0 && <span className="ml-1 text-xs font-normal text-ink-muted">({Math.round((convertidas.length / Math.max(1, inds.filter((i) => i.status !== 'cancelada').length)) * 100)}%)</span>}</p></div>
              <div><p className="text-xs uppercase text-ink-muted">Presentes entregues</p><p className="font-semibold tabular-nums">{convertidas.filter((i) => i.presente_entregue_em).length}</p></div>
              <div><p className="text-xs uppercase text-ink-muted">Custo dos presentes</p><p className="font-semibold tabular-nums text-red-700">{formatarMoeda(custoPresentes)}</p></div>
              <div><p className="text-xs uppercase text-ink-muted">Mensalidade gerada</p><p className="font-semibold tabular-nums text-green-700">{formatarMoeda(mrrGerado)}/mês</p></div>
            </div>
            {(converter.error || cancelar.error || escolherPresente.error || entregar.error) && <div className="p-4"><Alerta tipo="erro">{mensagemDeErro(converter.error ?? cancelar.error ?? escolherPresente.error ?? entregar.error)}</Alerta></div>}
            {inds.length === 0 ? <p className="px-6 py-8 text-center text-sm text-ink-muted">Nenhuma indicação recebida.</p> : (
              <div className="overflow-x-auto"><table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-6 py-3">Data</th><th className="px-6 py-3">Indicado</th><th className="px-6 py-3">Indicado por</th><th className="px-6 py-3">Status</th><th className="px-6 py-3"></th></tr></thead>
                <tbody>{inds.map((i) => (
                  <tr key={i.id} className="border-b border-line last:border-0">
                    <td className="px-6 py-3 tabular-nums text-ink-muted">{formatarData(i.criado_em.slice(0, 10))}</td>
                    <td className="px-6 py-3"><span className="font-medium">{i.nome_indicado}</span><span className="ml-2 text-ink-muted">{formatarTelefone(i.telefone_indicado)}</span>{i.indicado_pessoa_id && <p className="text-xs text-ink-muted">Cliente: {nomePessoa.get(i.indicado_pessoa_id) ?? '—'}</p>}</td>
                    <td className="px-6 py-3">{nomePessoa.get(i.indicador_pessoa_id) ?? '—'}</td>
                    <td className="px-6 py-3"><Distintivo tom={i.status === 'convertida' ? 'ok' : i.status === 'pendente' ? 'info' : 'neutro'}>{i.status === 'convertida' ? `Convertida${i.beneficio_valor > 0 ? ` · ${formatarMoeda(i.beneficio_valor)}` : ''}` : i.status === 'pendente' ? 'Aguardando' : 'Cancelada'}</Distintivo>{i.observacao && <p className="text-xs text-ink-muted">{i.observacao}</p>}</td>
                    <td className="px-6 py-3 text-right whitespace-nowrap">
                      {i.status === 'pendente' && <><Botao variante="secundario" onClick={() => setJanela({ tipo: 'converter', indicacao: i })}>Converter</Botao> <button type="button" className="ml-2 text-xs text-ink-muted hover:underline" onClick={() => cancelar.mutate({ id: i.id, observacao: 'Cancelada pelo administrador' })}>cancelar</button></>}
                      {i.status === 'convertida' && i.presente_entregue_em && <span className="text-xs text-ink-muted">🎁 {nomeItem.get(i.presente_item_id ?? '') ?? 'Presente'} entregue em {formatarData(i.presente_entregue_em)}</span>}
                      {i.status === 'convertida' && !i.presente_entregue_em && (
                        <span className="inline-flex items-center gap-2">
                          {i.convertida_em && diasUteisDesde(i.convertida_em) > 10 && <Distintivo tom="alerta">{`entrega atrasada (${diasUteisDesde(i.convertida_em)} dias úteis)`}</Distintivo>}
                          {i.presente_item_id ? (
                            <><span className="text-xs text-ink-muted">🎁 {nomeItem.get(i.presente_item_id) ?? '—'}</span><Botao variante="secundario" carregando={entregar.isPending} onClick={() => entregar.mutate({ id: i.id })}>Entregue</Botao></>
                          ) : (
                            <>
                              <select aria-label="Presente" value={presenteSel[i.id] ?? ''} onChange={(e) => setPresenteSel((m) => ({ ...m, [i.id]: e.target.value }))} className="h-9 rounded-md border border-line bg-white px-2 text-xs">
                                <option value="">Aguardando escolha…</option>
                                {brindes.map((b) => <option key={b.id} value={b.id}>{b.nome}</option>)}
                              </select>
                              <Botao variante="secundario" disabled={!presenteSel[i.id]} carregando={escolherPresente.isPending} onClick={() => escolherPresente.mutate({ id: i.id, itemId: presenteSel[i.id] })}>Registrar escolha</Botao>
                            </>
                          )}
                        </span>
                      )}
                    </td>
                  </tr>))}</tbody>
              </table></div>
            )}
            <p className="px-6 py-3 text-xs text-ink-muted">Converter = a pessoa indicada virou cliente (cadastrada em Pessoas). O indicante escolhe o presente pelo portal (a faixa vem do plano do indicado); "Entregue" baixa o estoque e congela o custo. Prazo: 10 dias úteis.</p>
          </Cartao>
          <VitrinePremiosAdmin negocioId={negocio.id} negocioSlug={negocio.slug} />
        </div>
      )}
      {negocio && (
        <Modal aberto={janela !== null} aoFechar={fechar} titulo={janela?.tipo === 'nova-indicacao' ? 'Nova indicação (recebida pelo WhatsApp)' : 'Converter indicação'}>
          {janela?.tipo === 'nova-indicacao' && (
            <div className="space-y-4">
              {criarInd.error != null && <Alerta tipo="erro">{mensagemDeErro(criarInd.error)}</Alerta>}
              <Selecao rotulo="Quem indicou (cliente)" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(pessoas.data ?? []).filter((p) => p.ativo).map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={novoIndicante} onChange={(e) => setNovoIndicante(e.target.value)} />
              <div className="grid grid-cols-2 gap-4">
                <Campo rotulo="Nome do indicado" value={novoNome} onChange={(e) => setNovoNome(e.target.value)} maxLength={120} />
                <Campo rotulo="Telefone (com DDD)" inputMode="tel" value={novoTel} onChange={(e) => setNovoTel(e.target.value)} />
              </div>
              <p className="text-xs text-ink-muted">O sistema barra telefone já indicado e telefone que já é de cliente (regra da campanha).</p>
              <div className="flex justify-end"><Botao onClick={() => criarInd.mutate({ negocioId: negocio.id, indicanteId: novoIndicante, nome: novoNome.trim(), telefone: novoTel }, { onSuccess: fechar })} disabled={!novoIndicante || novoNome.trim().length < 2 || novoTel.replace(/\D/g, '').length < 10} carregando={criarInd.isPending}>Registrar indicação</Botao></div>
            </div>
          )}
          {janela?.tipo === 'converter' && (
            <div className="space-y-4">
              <p className="text-sm">Indicação de <span className="font-medium">{janela.indicacao.nome_indicado}</span> ({formatarTelefone(janela.indicacao.telefone_indicado)}). Selecione o cadastro da pessoa que virou cliente.</p>
              <Selecao rotulo="Pessoa (cliente novo)" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(pessoas.data ?? []).filter((p) => p.ativo && p.id !== janela.indicacao.indicador_pessoa_id).map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={pessoaConv} onChange={(e) => setPessoaConv(e.target.value)} />
              {config?.beneficio_tipo === 'mes_gratis' ? <p className="text-xs text-ink-muted">Quem indicou ganha 1 mês grátis (100% da próxima fatura).</p> : config && config.beneficio_indicacao > 0 ? <p className="text-xs text-ink-muted">Quem indicou recebe {formatarMoeda(config.beneficio_indicacao)} de desconto na próxima fatura.</p> : <p className="text-xs text-ink-muted">Sem benefício em dinheiro configurado — o presente é o prêmio.</p>}
              <div className="flex justify-end"><Botao onClick={() => converter.mutate({ id: janela.indicacao.id, pessoaId: pessoaConv }, { onSuccess: fechar })} disabled={!pessoaConv} carregando={converter.isPending}>Confirmar conversão</Botao></div>
            </div>
          )}
        </Modal>
      )}
    </>
  )
}
