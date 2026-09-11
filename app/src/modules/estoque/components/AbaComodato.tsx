import { useMemo, useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Modal } from '../../../core/ui/Modal'
import { Cartao } from '../../../core/ui/Cartao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData } from '../../../core/formatos'
import { usePessoas } from '../../pessoas/api'
import { useContratos } from '../../contratos/api'
import { codigoContrato } from '../../contratos/tipos'
import { useTecnicos } from '../../os/api'
import { useComodatos, useEstoqueItens, usePerdaComodato, useRecolherComodato, useRegistrarComodato, useTrocarComodato } from '../api'
import { ROTULO_COMODATO, type Comodato } from '../tipos'

const TOM = { instalado: 'ok', recolhido: 'neutro', trocado: 'info', perdido: 'alerta' } as const

/** Equipamentos em comodato na casa dos clientes (onde está cada ONU). */
export function AbaComodato({ negocioId }: { negocioId: string }) {
  const comodatos = useComodatos()
  const itens = useEstoqueItens()
  const pessoas = usePessoas()
  const contratos = useContratos()
  const tecnicos = useTecnicos()
  const registrar = useRegistrarComodato(); const recolher = useRecolherComodato()
  const trocar = useTrocarComodato(); const perda = usePerdaComodato()

  const [busca, setBusca] = useState('')
  const [filtro, setFiltro] = useState('instalado')
  const [modal, setModal] = useState<'registrar' | null>(null)
  const [acao, setAcao] = useState<{ tipo: 'recolher' | 'trocar' | 'perda'; c: Comodato } | null>(null)
  const [itemId, setItemId] = useState(''); const [serie, setSerie] = useState(''); const [pessoaId, setPessoaId] = useState(''); const [contratoId, setContratoId] = useState('')
  const [motivo, setMotivo] = useState(''); const [descartar, setDescartar] = useState(false); const [defeito, setDefeito] = useState(false); const [tecnicoId, setTecnicoId] = useState(''); const [serieNova, setSerieNova] = useState('')

  const nomeItem = useMemo(() => new Map((itens.data ?? []).map((i) => [i.id, `${i.codigo} · ${i.nome}`])), [itens.data])
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const rotuloContrato = (id: string | null) => { const c = (contratos.data ?? []).find((x) => x.id === id); return c ? codigoContrato(c) : null }
  const lista = (comodatos.data ?? []).filter((c) => c.negocio_id === negocioId)
    .filter((c) => !filtro || c.status === filtro)
    .filter((c) => !busca.trim() || c.numero_serie.toLowerCase().includes(busca.toLowerCase()) || (nomePessoa.get(c.pessoa_id) ?? '').toLowerCase().includes(busca.toLowerCase()))
  const contratosDoCliente = (contratos.data ?? []).filter((c) => c.pessoa_id === pessoaId && c.negocio_id === negocioId && c.status !== 'encerrado')
  const tecnicosAtivos = (tecnicos.data ?? []).filter((t) => t.negocio_id === negocioId && t.ativo)
  const erro = registrar.error ?? recolher.error ?? trocar.error ?? perda.error
  const ocupado = registrar.isPending || recolher.isPending || trocar.isPending || perda.isPending

  function confirmarAcao() {
    if (!acao) return
    const fechar = { onSuccess: () => { setAcao(null); setMotivo(''); setSerieNova(''); setDescartar(false); setDefeito(false) } }
    if (acao.tipo === 'recolher') recolher.mutate({ p_comodato_id: acao.c.id, p_descartar: descartar, p_observacao: motivo.trim() || null }, fechar)
    if (acao.tipo === 'perda') perda.mutate({ p_comodato_id: acao.c.id, p_motivo: motivo.trim() }, fechar)
    if (acao.tipo === 'trocar') trocar.mutate({ p_comodato_id: acao.c.id, p_serie_nova: serieNova.trim(), p_tecnico_id: tecnicoId, p_defeito_fabrica: defeito, p_motivo: motivo.trim() }, fechar)
  }

  return (
    <Cartao className="p-0">
      <div className="flex flex-wrap items-center gap-2 border-b border-line px-4 py-3 text-sm">
        <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar série ou cliente…" className="h-9 w-56 rounded-md border border-line bg-white px-3" />
        <select aria-label="Status" value={filtro} onChange={(e) => setFiltro(e.target.value)} className="h-9 rounded-md border border-line bg-white px-2">
          <option value="">Todos</option><option value="instalado">Instalados</option><option value="recolhido">Recolhidos</option><option value="trocado">Trocados</option><option value="perdido">Perdidos</option>
        </select>
        <span className="text-ink-muted">{lista.length} equipamento(s)</span>
        <span className="flex-1" />
        <Botao variante="secundario" onClick={() => { setItemId(''); setSerie(''); setPessoaId(''); setContratoId(''); setModal('registrar') }}>Registrar equipamento antigo</Botao>
      </div>
      {erro != null && <div className="px-4 pt-3"><Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta></div>}
      {lista.length === 0 ? <p className="px-6 py-12 text-center text-sm text-ink-muted">Nenhum equipamento. Eles entram sozinhos quando o técnico encerra uma OS informando a série, ou registre um antigo.</p> : (
        <div className="overflow-x-auto"><table className="w-full text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-4 py-2 font-medium">Série</th><th className="px-4 py-2 font-medium">Equipamento</th><th className="px-4 py-2 font-medium">Cliente</th><th className="px-4 py-2 font-medium">Contrato</th><th className="px-4 py-2 font-medium">Instalado em</th><th className="px-4 py-2 font-medium">Status</th><th className="px-4 py-2"></th></tr></thead>
          <tbody>
            {lista.map((c) => (
              <tr key={c.id} className="border-b border-line last:border-0 hover:bg-surface">
                <td className="px-4 py-2 font-mono text-xs">{c.numero_serie}</td>
                <td className="px-4 py-2">{nomeItem.get(c.item_id) ?? '—'}</td>
                <td className="px-4 py-2">{nomePessoa.get(c.pessoa_id) ?? '—'}</td>
                <td className="px-4 py-2 text-ink-muted">{rotuloContrato(c.contrato_id) ?? '—'}</td>
                <td className="whitespace-nowrap px-4 py-2 tabular-nums">{formatarData(c.data_instalacao)}{c.data_recolhimento ? ` → ${formatarData(c.data_recolhimento)}` : ''}</td>
                <td className="px-4 py-2"><Distintivo tom={TOM[c.status]}>{ROTULO_COMODATO[c.status]}</Distintivo></td>
                <td className="whitespace-nowrap px-4 py-2 text-right text-xs">
                  {c.status === 'instalado' && (
                    <>
                      <button type="button" className="text-brand-700 hover:underline" onClick={() => { setAcao({ tipo: 'trocar', c }); setMotivo(''); setSerieNova(''); setTecnicoId(tecnicosAtivos[0]?.id ?? '') }}>Trocar</button>
                      <button type="button" className="ml-3 text-brand-700 hover:underline" onClick={() => { setAcao({ tipo: 'recolher', c }); setMotivo('') }}>Recolher</button>
                      <button type="button" className="ml-3 text-red-700 hover:underline" onClick={() => { setAcao({ tipo: 'perda', c }); setMotivo('') }}>Perda</button>
                    </>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table></div>
      )}

      <Modal aberto={modal === 'registrar'} aoFechar={() => { setModal(null); registrar.reset() }} largura="md" titulo="Registrar equipamento antigo">
        {modal === 'registrar' && (
          <div className="space-y-4">
            {registrar.error != null && <Alerta tipo="erro">{mensagemDeErro(registrar.error)}</Alerta>}
            <p className="text-xs text-ink-muted">Para equipamento que já estava na casa do cliente antes do sistema. Não mexe no estoque.</p>
            <Selecao rotulo="Equipamento" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(itens.data ?? []).filter((i) => i.negocio_id === negocioId && i.ativo).map((i) => ({ valor: i.id, rotulo: `${i.codigo} · ${i.nome}` }))]} value={itemId} onChange={(e) => setItemId(e.target.value)} />
            <Campo rotulo="Número de série" value={serie} onChange={(e) => setSerie(e.target.value)} maxLength={40} />
            <Selecao rotulo="Cliente" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(pessoas.data ?? []).filter((p) => p.ativo).map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={pessoaId} onChange={(e) => { setPessoaId(e.target.value); setContratoId('') }} />
            <Selecao rotulo="Contrato (opcional)" opcoes={[{ valor: '', rotulo: 'Nenhum' }, ...contratosDoCliente.map((c) => ({ valor: c.id, rotulo: codigoContrato(c) }))]} value={contratoId} onChange={(e) => setContratoId(e.target.value)} disabled={!pessoaId} />
            <div className="flex justify-end"><Botao disabled={!itemId || serie.trim().length < 3 || !pessoaId} carregando={registrar.isPending}
              onClick={() => registrar.mutate({ p_negocio_id: negocioId, p_item_id: itemId, p_serie: serie.trim(), p_pessoa_id: pessoaId, p_contrato_id: contratoId || null }, { onSuccess: () => setModal(null) })}>Registrar</Botao></div>
          </div>
        )}
      </Modal>

      <Modal aberto={acao !== null} aoFechar={() => setAcao(null)} largura="md" titulo={acao ? `${acao.tipo === 'recolher' ? 'Recolher' : acao.tipo === 'trocar' ? 'Trocar' : 'Perda de'} ${acao.c.numero_serie}` : ''}>
        {acao && (
          <div className="space-y-4">
            {erro != null && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}
            {acao.tipo === 'recolher' && (
              <>
                <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={descartar} onChange={(e) => setDescartar(e.target.checked)} className="size-4 accent-brand-600" />Descartar (danificado — não volta ao estoque)</label>
                <Campo rotulo={descartar ? 'Motivo do descarte' : 'Observação (opcional)'} value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={300} />
                <p className="text-xs text-ink-muted">{descartar ? 'Fica só o histórico.' : 'O equipamento volta ao estoque central pelo custo médio.'}</p>
              </>
            )}
            {acao.tipo === 'perda' && <Campo rotulo="Justificativa (obrigatória)" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={300} autoFocus />}
            {acao.tipo === 'trocar' && (
              <>
                <Campo rotulo="Série do equipamento novo" value={serieNova} onChange={(e) => setSerieNova(e.target.value)} maxLength={40} autoFocus />
                <Selecao rotulo="Técnico (o novo sai da bolsa dele)" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...tecnicosAtivos.map((t) => ({ valor: t.id, rotulo: t.nome }))]} value={tecnicoId} onChange={(e) => setTecnicoId(e.target.value)} />
                <Campo rotulo="Motivo da troca" value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={300} />
                <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={defeito} onChange={(e) => setDefeito(e.target.checked)} className="size-4 accent-brand-600" />Defeito de fábrica (o antigo não volta ao estoque)</label>
              </>
            )}
            <div className="flex justify-end gap-2">
              <Botao variante="secundario" onClick={() => setAcao(null)} disabled={ocupado}>Cancelar</Botao>
              <Botao variante={acao.tipo === 'perda' ? 'perigo' : 'primario'} carregando={ocupado} onClick={confirmarAcao}
                disabled={(acao.tipo === 'perda' && motivo.trim().length < 3) || (acao.tipo === 'recolher' && descartar && motivo.trim().length < 3) || (acao.tipo === 'trocar' && (serieNova.trim().length < 3 || !tecnicoId || motivo.trim().length < 3))}>
                Confirmar
              </Botao>
            </div>
          </div>
        )}
      </Modal>
    </Cartao>
  )
}
