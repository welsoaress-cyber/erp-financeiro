import { useMemo, useState, type FormEvent } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { AreaTexto } from '../../../core/ui/AreaTexto'
import { Selecao } from '../../../core/ui/Selecao'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda, hojeISO } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { usePlanos } from '../../contratos/api'
import { formatarTelefone } from '../../pessoas/tipos'
import { useAcessosPortal, useCancelarIndicacao, useConverterIndicacao, useIndicacoesAdmin, usePortalConfigs, usePromocoesAdmin, useSalvarPortalConfig, useSalvarPromocao } from '../api'
import type { IndicacaoAdmin, PortalConfig, PromocaoAdmin } from '../tipos'

type Janela = { tipo: 'config' } | { tipo: 'promocao'; promocao?: PromocaoAdmin } | { tipo: 'converter'; indicacao: IndicacaoAdmin } | null

function FormConfig({ negocioId, config, aoConcluir }: { negocioId: string; config: PortalConfig | null; aoConcluir: () => void }) {
  const salvar = useSalvarPortalConfig()
  const [ativo, setAtivo] = useState(config?.ativo ?? true); const [logo, setLogo] = useState(config?.logo_url ?? ''); const [cor, setCor] = useState(config?.cor_primaria ?? '#1e3a8a')
  const [texto, setTexto] = useState(config?.texto_promocional ?? ''); const [pix, setPix] = useState(config?.chave_pix ?? ''); const [instr, setInstr] = useState(config?.instrucoes_pagamento ?? ''); const [beneficio, setBeneficio] = useState(String(config?.beneficio_indicacao ?? 0))
  const [erro, setErro] = useState<string | null>(null)
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    const b = Number(beneficio.replace(',', '.')); if (Number.isNaN(b) || b < 0) { setErro('Benefício inválido.'); return }
    if (logo && !/^https:\/\//.test(logo)) { setErro('O logo deve ser um endereço https://'); return }
    if (!/^#[0-9a-fA-F]{6}$/.test(cor)) { setErro('Cor no formato #RRGGBB.'); return }
    setErro(null)
    salvar.mutate({ id: config?.id, negocioId, dados: { ativo, logo_url: logo || null, cor_primaria: cor, texto_promocional: texto.trim() || null, chave_pix: pix.trim() || null, instrucoes_pagamento: instr.trim() || null, beneficio_indicacao: Math.round(b * 100) / 100 } }, { onSuccess: aoConcluir })
  }
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || salvar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(salvar.error)}</Alerta>}
      <div className="grid gap-4 sm:grid-cols-2">
        <Campo rotulo="Cor principal" type="color" value={cor} onChange={(e) => setCor(e.target.value)} className="h-10 p-1" />
        <Campo rotulo="Logo (URL https)" value={logo} onChange={(e) => setLogo(e.target.value)} placeholder="https://…/logo.png" />
        <Campo rotulo="Chave Pix (aparece na fatura)" value={pix} onChange={(e) => setPix(e.target.value)} />
        <Campo rotulo="Benefício por indicação convertida (R$)" type="number" step="0.01" min="0" value={beneficio} onChange={(e) => setBeneficio(e.target.value)} />
      </div>
      <AreaTexto rotulo="Texto promocional (aparece no início do portal)" rows={2} maxLength={500} value={texto} onChange={(e) => setTexto(e.target.value)} />
      <AreaTexto rotulo="Instruções de pagamento (aparecem na fatura)" rows={2} maxLength={500} value={instr} onChange={(e) => setInstr(e.target.value)} />
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} className="size-4 accent-brand-600" />Portal ativo para este negócio</label>
      <div className="flex justify-end"><Botao type="submit" carregando={salvar.isPending}>Salvar</Botao></div>
    </form>
  )
}

function FormPromocao({ negocioId, promocao, aoConcluir }: { negocioId: string; promocao?: PromocaoAdmin; aoConcluir: () => void }) {
  const salvar = useSalvarPromocao(); const planos = usePlanos()
  const [titulo, setTitulo] = useState(promocao?.titulo ?? ''); const [descricao, setDescricao] = useState(promocao?.descricao ?? ''); const [regras, setRegras] = useState(promocao?.regras ?? ''); const [aderir, setAderir] = useState(promocao?.como_aderir ?? '')
  const [inicio, setInicio] = useState(promocao?.data_inicio ?? hojeISO()); const [fim, setFim] = useState(promocao?.data_fim ?? ''); const [planoId, setPlanoId] = useState(promocao?.plano_id ?? ''); const [ativa, setAtiva] = useState(promocao?.ativa ?? true)
  const [erro, setErro] = useState<string | null>(null)
  const meusPlanos = (planos.data ?? []).filter((p) => p.negocio_id === negocioId)
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (titulo.trim().length < 3) { setErro('Título com pelo menos 3 caracteres.'); return }
    if (descricao.trim().length < 3) { setErro('Descreva a promoção.'); return }
    if (fim && fim < inicio) { setErro('Fim antes do início.'); return }
    setErro(null)
    salvar.mutate({ id: promocao?.id, dados: { negocio_id: negocioId, plano_id: planoId || null, titulo: titulo.trim(), descricao: descricao.trim(), regras: regras.trim() || null, como_aderir: aderir.trim() || null, data_inicio: inicio, data_fim: fim || null, ativa } }, { onSuccess: aoConcluir })
  }
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || salvar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(salvar.error)}</Alerta>}
      <Campo rotulo="Título" value={titulo} onChange={(e) => setTitulo(e.target.value)} maxLength={100} autoFocus />
      <AreaTexto rotulo="Descrição" rows={3} maxLength={1000} value={descricao} onChange={(e) => setDescricao(e.target.value)} />
      <AreaTexto rotulo="Regras (opcional)" rows={2} maxLength={1000} value={regras} onChange={(e) => setRegras(e.target.value)} />
      <Campo rotulo="Como aderir (opcional)" value={aderir} onChange={(e) => setAderir(e.target.value)} maxLength={500} />
      <div className="grid gap-4 sm:grid-cols-3">
        <Campo rotulo="Início" type="date" value={inicio} onChange={(e) => setInicio(e.target.value)} />
        <Campo rotulo="Fim (opcional)" type="date" value={fim} onChange={(e) => setFim(e.target.value)} />
        <Selecao rotulo="Restrita ao plano" opcoes={[{ valor: '', rotulo: 'Todos os clientes' }, ...meusPlanos.map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={planoId} onChange={(e) => setPlanoId(e.target.value)} />
      </div>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={ativa} onChange={(e) => setAtiva(e.target.checked)} className="size-4 accent-brand-600" />Promoção ativa</label>
      <div className="flex justify-end"><Botao type="submit" carregando={salvar.isPending}>{promocao ? 'Salvar alterações' : 'Criar promoção'}</Botao></div>
    </form>
  )
}

export function PortalAdminPage() {
  const negocios = useNegocios(); const configs = usePortalConfigs(); const promocoes = usePromocoesAdmin(); const indicacoes = useIndicacoesAdmin(); const acessos = useAcessosPortal(); const pessoas = usePessoas()
  const converter = useConverterIndicacao(); const cancelar = useCancelarIndicacao()
  const [negocioSel, setNegocioSel] = useState(''); const [janela, setJanela] = useState<Janela>(null); const [pessoaConv, setPessoaConv] = useState('')
  const ativos = useMemo(() => (negocios.data ?? []).filter((n) => n.ativo), [negocios.data])
  const negocio = ativos.find((n) => n.id === negocioSel) ?? ativos[0] ?? null
  const config = (configs.data ?? []).find((c) => c.negocio_id === negocio?.id) ?? null
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])
  const promos = (promocoes.data ?? []).filter((p) => p.negocio_id === negocio?.id)
  const inds = (indicacoes.data ?? []).filter((i) => i.negocio_id === negocio?.id)
  const fechar = () => { setJanela(null); setPessoaConv('') }
  if (negocios.isPending || configs.isPending) return <><CabecalhoPagina titulo="Portal do cliente" /><Carregando /></>
  return (
    <>
      <CabecalhoPagina titulo="Portal do cliente" descricao="Aparência, Pix, promoções e Indique e Ganhe. Clientes acessam em /portal" acoes={negocio ? <Botao variante="secundario" onClick={() => setJanela({ tipo: 'config' })}>{config ? 'Configurar portal' : 'Ativar portal'}</Botao> : undefined} />
      {!negocio && <Alerta tipo="info">Cadastre um negócio ativo antes.</Alerta>}
      {negocio && (
        <div className="space-y-6">
          <div className="flex flex-wrap items-center gap-3">
            {ativos.length > 1 && <select aria-label="Negócio" value={negocio.id} onChange={(e) => setNegocioSel(e.target.value)} className="h-10 rounded-md border border-line bg-white px-3 text-sm">{ativos.map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}</select>}
            <span className="text-sm text-ink-muted">{negocio.nome}{config ? ` · Pix ${config.chave_pix ?? 'não informado'} · benefício ${formatarMoeda(config.beneficio_indicacao)} por indicação` : ' · portal sem configuração'}</span>
            {config && <Distintivo tom={config.ativo ? 'ok' : 'neutro'}>{config.ativo ? 'Portal ativo' : 'Portal desativado'}</Distintivo>}
            <a href={`${window.location.origin}/portal/entrar`} target="_blank" rel="noreferrer" className="ml-auto text-sm text-brand-700 hover:underline">Abrir portal</a>
          </div>
          <div className="grid gap-6 lg:grid-cols-2">
            <Cartao>
              <div className="mb-3 flex items-center justify-between"><h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Promoções</h2><Botao variante="secundario" onClick={() => setJanela({ tipo: 'promocao' })}>Nova promoção</Botao></div>
              {promos.length === 0 ? <p className="text-sm text-ink-muted">Nenhuma promoção.</p> : <ul className="divide-y divide-line rounded-md border border-line">{promos.map((p) => <li key={p.id} className="flex items-center justify-between gap-3 px-3 py-2 text-sm"><button type="button" className="text-left" onClick={() => setJanela({ tipo: 'promocao', promocao: p })}><span className="font-medium">{p.titulo}</span><span className="text-ink-muted"> · {formatarData(p.data_inicio)}{p.data_fim ? ` a ${formatarData(p.data_fim)}` : ''}</span></button><Distintivo tom={p.ativa ? 'ok' : 'neutro'}>{p.ativa ? 'Ativa' : 'Inativa'}</Distintivo></li>)}</ul>}
            </Cartao>
            <Cartao>
              <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-ink-muted">Acessos ao portal</h2>
              {acessos.isPending ? <Carregando /> : (acessos.data ?? []).length === 0 ? <p className="text-sm text-ink-muted">Nenhum cliente criou acesso ainda. Eles se cadastram em /portal/cadastro com CPF/CNPJ e telefone.</p> : <ul className="divide-y divide-line rounded-md border border-line">{(acessos.data ?? []).map((a) => <li key={a.id} className="flex items-center justify-between px-3 py-2 text-sm"><span>{a.pessoa}<span className="ml-2 font-mono text-xs text-ink-muted">{a.codigo_indicacao}</span></span><span className="text-xs text-ink-muted">{a.indicacoes} indicação(ões) · desde {formatarData(a.criado_em.slice(0, 10))}</span></li>)}</ul>}
            </Cartao>
          </div>
          <Cartao className="p-0">
            <div className="border-b border-line px-6 py-3"><h2 className="text-sm font-semibold uppercase tracking-wide text-ink-muted">Indicações (Indique e Ganhe)</h2></div>
            {(converter.error || cancelar.error) && <div className="p-4"><Alerta tipo="erro">{mensagemDeErro(converter.error ?? cancelar.error)}</Alerta></div>}
            {inds.length === 0 ? <p className="px-6 py-8 text-center text-sm text-ink-muted">Nenhuma indicação recebida.</p> : (
              <div className="overflow-x-auto"><table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-ink-muted"><tr className="border-b border-line"><th className="px-6 py-3">Data</th><th className="px-6 py-3">Indicado</th><th className="px-6 py-3">Indicado por</th><th className="px-6 py-3">Status</th><th className="px-6 py-3"></th></tr></thead>
                <tbody>{inds.map((i) => (
                  <tr key={i.id} className="border-b border-line last:border-0">
                    <td className="px-6 py-3 tabular-nums text-ink-muted">{formatarData(i.criado_em.slice(0, 10))}</td>
                    <td className="px-6 py-3"><span className="font-medium">{i.nome_indicado}</span><span className="ml-2 text-ink-muted">{formatarTelefone(i.telefone_indicado)}</span>{i.indicado_pessoa_id && <p className="text-xs text-ink-muted">Cliente: {nomePessoa.get(i.indicado_pessoa_id) ?? '—'}</p>}</td>
                    <td className="px-6 py-3">{nomePessoa.get(i.indicador_pessoa_id) ?? '—'}</td>
                    <td className="px-6 py-3"><Distintivo tom={i.status === 'convertida' ? 'ok' : i.status === 'pendente' ? 'info' : 'neutro'}>{i.status === 'convertida' ? `Convertida${i.beneficio_valor > 0 ? ` · ${formatarMoeda(i.beneficio_valor)}` : ''}` : i.status === 'pendente' ? 'Aguardando' : 'Cancelada'}</Distintivo>{i.observacao && <p className="text-xs text-ink-muted">{i.observacao}</p>}</td>
                    <td className="px-6 py-3 text-right whitespace-nowrap">{i.status === 'pendente' && <><Botao variante="secundario" onClick={() => setJanela({ tipo: 'converter', indicacao: i })}>Converter</Botao> <button type="button" className="ml-2 text-xs text-ink-muted hover:underline" onClick={() => cancelar.mutate({ id: i.id, observacao: 'Cancelada pelo administrador' })}>cancelar</button></>}</td>
                  </tr>))}</tbody>
              </table></div>
            )}
            <p className="px-6 py-3 text-xs text-ink-muted">Converter = a pessoa indicada virou cliente (cadastrada em Pessoas). O benefício vira desconto na próxima fatura de quem indicou.</p>
          </Cartao>
        </div>
      )}
      {negocio && (
        <Modal aberto={janela !== null} aoFechar={fechar} titulo={janela?.tipo === 'config' ? `Portal · ${negocio.nome}` : janela?.tipo === 'promocao' ? (janela.promocao ? 'Editar promoção' : 'Nova promoção') : 'Converter indicação'}>
          {janela?.tipo === 'config' && <FormConfig negocioId={negocio.id} config={config} aoConcluir={fechar} />}
          {janela?.tipo === 'promocao' && <FormPromocao negocioId={negocio.id} promocao={janela.promocao} aoConcluir={fechar} />}
          {janela?.tipo === 'converter' && (
            <div className="space-y-4">
              <p className="text-sm">Indicação de <span className="font-medium">{janela.indicacao.nome_indicado}</span> ({formatarTelefone(janela.indicacao.telefone_indicado)}). Selecione o cadastro da pessoa que virou cliente.</p>
              <Selecao rotulo="Pessoa (cliente novo)" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...(pessoas.data ?? []).filter((p) => p.ativo && p.id !== janela.indicacao.indicador_pessoa_id).map((p) => ({ valor: p.id, rotulo: p.nome }))]} value={pessoaConv} onChange={(e) => setPessoaConv(e.target.value)} />
              {config && config.beneficio_indicacao > 0 ? <p className="text-xs text-ink-muted">Quem indicou recebe {formatarMoeda(config.beneficio_indicacao)} de desconto na próxima fatura.</p> : <p className="text-xs text-ink-muted">Sem benefício configurado para este negócio.</p>}
              <div className="flex justify-end"><Botao onClick={() => converter.mutate({ id: janela.indicacao.id, pessoaId: pessoaConv }, { onSuccess: fechar })} disabled={!pessoaConv} carregando={converter.isPending}>Confirmar conversão</Botao></div>
            </div>
          )}
        </Modal>
      )}
    </>
  )
}
