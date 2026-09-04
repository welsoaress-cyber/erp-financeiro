import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { SeletorMes } from '../../../core/ui/SeletorMes'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../../core/formatos'
import { usePeriodo } from '../../../core/periodo/usePeriodo'
import { useOrganizacao } from '../../../core/organizacao/useOrganizacao'
import { useContas } from '../../contas/api'
import { useCategorias } from '../../categorias/api'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useContratos } from '../../contratos/api'
import { codigoContrato } from '../../contratos/tipos'
import { ROTULO_PESSOAL } from '../../negocios/tipos'
import { buscarPossiveisDuplicados, useAtualizarLancamento, useAtualizarLancamentoRecorrente, useCancelarLancamento, useCriarLancamento, useEfetivarLancamento, useExcluirLancamento, useLancamentos, useProjetarLancamento, useProximaParcela } from '../api'
import { FormularioLancamento } from '../components/FormularioLancamento'
import { AcoesLancamento } from '../components/AcoesLancamento'
import { ROTULO_PERIODICIDADE, ROTULO_STATUS, ROTULO_TIPO, rotuloParcela, type DadosLancamento, type Lancamento, type StatusLancamento, type TipoLancamento } from '../tipos'

type Edicao = { modo: 'novo' } | { modo: 'editar'; lancamento: Lancamento } | null
const TOM_STATUS: Record<StatusLancamento, 'ok' | 'alerta' | 'neutro'> = { efetivado: 'ok', previsto: 'alerta', cancelado: 'neutro' }

export function LancamentosPage() {
  const { organizacao } = useOrganizacao()
  const { mes, setMes } = usePeriodo()
  const [filtroTipo, setFiltroTipo] = useState<TipoLancamento | ''>('')
  const [filtroStatus, setFiltroStatus] = useState<StatusLancamento | ''>('')
  const [filtroNegocio, setFiltroNegocio] = useState<string>('') // '' = todos, 'pessoal', ou id
  const [edicao, setEdicao] = useState<Edicao>(null)
  const [avisoDuplicidade, setAvisoDuplicidade] = useState<string | null>(null)

  const lancamentos = useLancamentos(mes)
  const contas = useContas()
  const categorias = useCategorias()
  const negocios = useNegocios()
  const pessoas = usePessoas()
  const contratos = useContratos()
  const criar = useCriarLancamento()
  const atualizar = useAtualizarLancamento()
  const efetivar = useEfetivarLancamento()
  const cancelar = useCancelarLancamento()
  const excluir = useExcluirLancamento()
  const projetar = useProjetarLancamento()
  const atualizarLote = useAtualizarLancamentoRecorrente()
  const emEdicao = edicao?.modo === 'editar' ? edicao.lancamento : null
  const proximaParcela = useProximaParcela(emEdicao?.id ?? null, emEdicao?.recorrente ?? false)

  const nomeConta = useMemo(() => new Map((contas.data ?? []).map((c) => [c.id, c.nome])), [contas.data])
  const nomeCategoria = useMemo(() => new Map((categorias.data ?? []).map((c) => [c.id, c.nome])), [categorias.data])
  const nomeNegocio = useMemo(() => new Map((negocios.data ?? []).map((n) => [n.id, n.nome])), [negocios.data])
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const contratoPorId = useMemo(() => new Map((contratos.data ?? []).map((c) => [c.id, c])), [contratos.data])
  const temNegocios = (negocios.data ?? []).length > 0

  const lista = (lancamentos.data ?? []).filter((l) =>
    (!filtroTipo || l.tipo === filtroTipo)
    && (!filtroStatus || l.status === filtroStatus)
    && (!filtroNegocio || (filtroNegocio === 'pessoal' ? l.negocio_id === null : l.negocio_id === filtroNegocio)))
  const totais = lista.reduce((t, l) => {
    if (l.status !== 'efetivado') return t
    if (l.tipo === 'receita') t.receitas += l.valor
    if (l.tipo === 'despesa') t.despesas += l.valor
    return t
  }, { receitas: 0, despesas: 0 })

  function fechar() {
    criar.reset(); atualizar.reset(); efetivar.reset(); cancelar.reset(); excluir.reset(); projetar.reset(); atualizarLote.reset()
    setAvisoDuplicidade(null)
    setEdicao(null)
  }

  async function salvar(dados: DadosLancamento, ignorarDuplicidade: boolean) {
    if (!edicao) return
    if (!ignorarDuplicidade) {
      try {
        const iguais = await buscarPossiveisDuplicados(organizacao.id, dados, edicao.modo === 'editar' ? edicao.lancamento.id : undefined)
        if (iguais.length > 0) {
          setAvisoDuplicidade(`Já existe "${iguais[0].descricao}" de ${formatarMoeda(iguais[0].valor)} na mesma conta em ${formatarData(iguais[0].data_competencia)}.`)
          return
        }
      } catch { /* falha na checagem não impede salvar */ }
    }
    setAvisoDuplicidade(null)
    if (edicao.modo === 'novo') criar.mutate(dados, { onSuccess: fechar })
    else atualizar.mutate({ id: edicao.lancamento.id, ...dados }, { onSuccess: fechar })
  }

  const carregando = lancamentos.isPending || contas.isPending || categorias.isPending
  const erroCarga = lancamentos.error ?? contas.error ?? categorias.error
  const erroSalvar = criar.error ?? atualizar.error ?? atualizarLote.error
  const erroAcao = efetivar.error ?? cancelar.error ?? excluir.error ?? projetar.error
  const ocupadoAcao = efetivar.isPending || cancelar.isPending || excluir.isPending || projetar.isPending

  function descricaoSecundaria(l: Lancamento) {
    const base = l.tipo === 'transferencia'
      ? `${nomeConta.get(l.conta_id) ?? '—'} → ${nomeConta.get(l.conta_destino_id ?? '') ?? '—'}`
      : `${nomeCategoria.get(l.categoria_id ?? '') ?? '—'} · ${nomeConta.get(l.conta_id) ?? '—'}`
    const comNegocio = l.negocio_id ? `${base} · ${nomeNegocio.get(l.negocio_id) ?? '—'}` : base
    const comPessoa = l.pessoa_id ? `${comNegocio} · ${nomePessoa.get(l.pessoa_id) ?? '—'}` : comNegocio
    const c = l.contrato_id ? contratoPorId.get(l.contrato_id) : undefined
    return c ? `${comPessoa} · ${codigoContrato(c)}` : comPessoa
  }

  function classeValor(l: Lancamento) {
    if (l.status === 'cancelado') return 'text-ink-muted line-through'
    if (l.tipo === 'receita') return 'text-green-700'
    if (l.tipo === 'despesa') return 'text-red-700'
    return 'text-brand-700'
  }

  return (
    <>
      <CabecalhoPagina
        titulo="Lançamentos"
        descricao="Receitas, despesas e transferências"
        acoes={<Botao onClick={() => setEdicao({ modo: 'novo' })} disabled={(contas.data ?? []).length === 0}>Novo lançamento</Botao>}
      />

      {contas.isSuccess && contas.data.length === 0 && (
        <div className="mb-4"><Alerta tipo="info" titulo="Cadastre uma conta antes">Lançamentos precisam de uma conta. Crie sua primeira conta no menu Contas.</Alerta></div>
      )}

      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SeletorMes mes={mes} aoMudar={setMes} />
        <select aria-label="Filtrar por tipo" value={filtroTipo} onChange={(e) => setFiltroTipo(e.target.value as TipoLancamento | '')} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
          <option value="">Todos os tipos</option>
          <option value="receita">Receitas</option>
          <option value="despesa">Despesas</option>
          <option value="transferencia">Transferências</option>
        </select>
        <select aria-label="Filtrar por status" value={filtroStatus} onChange={(e) => setFiltroStatus(e.target.value as StatusLancamento | '')} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
          <option value="">Todos os status</option>
          <option value="efetivado">Efetivados</option>
          <option value="previsto">Previstos</option>
          <option value="cancelado">Cancelados</option>
        </select>
        {temNegocios && (
          <select aria-label="Filtrar por negócio" value={filtroNegocio} onChange={(e) => setFiltroNegocio(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">
            <option value="">Todos os negócios</option>
            <option value="pessoal">{ROTULO_PESSOAL}</option>
            {(negocios.data ?? []).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
          </select>
        )}
        <span className="ml-auto text-sm text-ink-muted tabular-nums">
          Receitas <span className="font-medium text-green-700">{formatarMoeda(totais.receitas)}</span> · Despesas <span className="font-medium text-red-700">{formatarMoeda(totais.despesas)}</span>
        </span>
      </div>

      {carregando && <Carregando texto="Carregando lançamentos…" />}
      {erroCarga && <Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(erroCarga)}</Alerta>}

      {lancamentos.isSuccess && contas.isSuccess && categorias.isSuccess && (
        <Cartao className="p-0">
          {lista.length === 0 ? (
            <div className="flex flex-col items-center gap-3 py-16 text-center">
              <p className="text-sm font-medium">Nenhum lançamento neste período</p>
              <p className="text-sm text-ink-muted">Use "Novo lançamento" para registrar uma receita, despesa ou transferência.</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                  <tr className="border-b border-line">
                    <th className="px-6 py-3 font-medium">Data</th>
                    <th className="px-6 py-3 font-medium">Descrição</th>
                    <th className="px-6 py-3 font-medium">Tipo</th>
                    <th className="px-6 py-3 text-right font-medium">Valor</th>
                    <th className="px-6 py-3 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {lista.map((l) => (
                    <tr key={l.id} onClick={() => setEdicao({ modo: 'editar', lancamento: l })} className="cursor-pointer border-b border-line last:border-0 hover:bg-surface">
                      <td className="whitespace-nowrap px-6 py-3 tabular-nums text-ink-muted">{formatarData(l.data_competencia)}</td>
                      <td className="px-6 py-3">
                        <div className="font-medium">
                          {l.descricao}
                          {l.origem === 'faturamento' && <span className="ml-2 align-middle"><Distintivo tom="info">Automático</Distintivo></span>}
                          {l.recorrente && <span className="ml-2 align-middle" title={l.numero_parcelas ? `Parcelamento · ${ROTULO_PERIODICIDADE[l.periodicidade!]}` : `${l.tipo === 'receita' ? 'Receita' : 'Despesa'} fixa · ${ROTULO_PERIODICIDADE[l.periodicidade!]}`}><Distintivo tom="info">{`🔄 ${rotuloParcela(l)}`}</Distintivo></span>}
                        </div>
                        <div className="text-xs text-ink-muted">{descricaoSecundaria(l)}</div>
                      </td>
                      <td className="whitespace-nowrap px-6 py-3 text-ink-muted">{ROTULO_TIPO[l.tipo]}</td>
                      <td className={`whitespace-nowrap px-6 py-3 text-right font-medium tabular-nums ${classeValor(l)}`}>
                        {l.tipo === 'despesa' ? '− ' : l.tipo === 'receita' ? '+ ' : ''}{formatarMoeda(l.valor)}
                      </td>
                      <td className="px-6 py-3"><Distintivo tom={TOM_STATUS[l.status]}>{ROTULO_STATUS[l.status]}</Distintivo></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Cartao>
      )}

      <Modal aberto={edicao !== null} aoFechar={fechar} titulo={edicao?.modo === 'editar' ? (edicao.lancamento.status === 'cancelado' ? 'Lançamento cancelado' : 'Editar lançamento') : 'Novo lançamento'}>
        {edicao && edicao.modo === 'editar' && edicao.lancamento.status === 'cancelado' && (
          <div className="space-y-3 text-sm">
            <p><span className="text-ink-muted">Descrição:</span> {edicao.lancamento.descricao}</p>
            <p><span className="text-ink-muted">Valor:</span> {formatarMoeda(edicao.lancamento.valor)} · {formatarData(edicao.lancamento.data_competencia)}</p>
            <AcoesLancamento lancamento={edicao.lancamento} ocupado={false} erro={null} aoEfetivar={() => {}} aoCancelarLancamento={() => {}} aoExcluir={() => {}} />
          </div>
        )}
        {edicao && !(edicao.modo === 'editar' && edicao.lancamento.status === 'cancelado') && (
          <div className="space-y-4">
            <FormularioLancamento
              key={edicao.modo === 'editar' ? edicao.lancamento.id : 'novo'}
              lancamento={edicao.modo === 'editar' ? edicao.lancamento : undefined}
              contas={contas.data ?? []}
              categorias={categorias.data ?? []}
              negocios={negocios.data ?? []}
              pessoas={pessoas.data ?? []}
              contratos={contratos.data ?? []}
              negocioInicial={filtroNegocio && filtroNegocio !== 'pessoal' ? filtroNegocio : null}
              tipoInicial={filtroTipo || 'despesa'}
              salvando={criar.isPending || atualizar.isPending || atualizarLote.isPending}
              erro={erroSalvar ? mensagemDeErro(erroSalvar) : null}
              avisoDuplicidade={avisoDuplicidade}
              proximaGerada={Boolean(proximaParcela.data)}
              aoSalvar={salvar}
              aoSalvarLote={edicao.modo === 'editar' ? (d) => atualizarLote.mutate({ id: edicao.lancamento.id, ...d }, { onSuccess: fechar }) : undefined}
              aoCancelar={fechar}
            />
            {edicao.modo === 'editar' && (
              <AcoesLancamento
                lancamento={edicao.lancamento}
                ocupado={ocupadoAcao}
                erro={erroAcao ? mensagemDeErro(erroAcao) : null}
                aoEfetivar={(data) => efetivar.mutate({ id: edicao.lancamento.id, data_efetivacao: data }, { onSuccess: fechar })}
                aoCancelarLancamento={(motivo) => cancelar.mutate({ id: edicao.lancamento.id, motivo }, { onSuccess: fechar })}
                aoExcluir={() => excluir.mutate(edicao.lancamento.id, { onSuccess: fechar })}
                aoProjetar={(meses) => projetar.mutate({ id: edicao.lancamento.id, meses }, { onSuccess: fechar })}
              />
            )}
          </div>
        )}
      </Modal>
    </>
  )
}
