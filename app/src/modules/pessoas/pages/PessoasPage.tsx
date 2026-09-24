import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { useNegocios } from '../../negocios/api'
import { useAlternarAtivoPessoa, useAtualizarPessoa, useCriarPessoa, useExcluirPessoa, usePessoas, useVinculos } from '../api'
import { FormularioPessoa } from '../components/FormularioPessoa'
import { VinculosPessoa } from '../components/VinculosPessoa'
import { formatarDocumento, formatarTelefone, PAPEIS_VINCULO, ROTULO_PAPEL, somenteDigitos, TIPOS_PESSOA, type DadosPessoa, type PapelVinculo, type TipoPessoa, type Vinculo } from '../tipos'

type Edicao = { modo: 'nova' } | { modo: 'editar'; pessoaId: string } | null

export function PessoasPage() {
  const pessoas = usePessoas()
  const vinculos = useVinculos()
  const negocios = useNegocios()
  const criar = useCriarPessoa()
  const atualizar = useAtualizarPessoa()
  const excluir = useExcluirPessoa()
  const alternarAtivo = useAlternarAtivoPessoa()
  const [busca, setBusca] = useState('')
  const [mostrarInativas, setMostrarInativas] = useState(false)
  const [filtroNegocio, setFiltroNegocio] = useState('') // '' = todos, 'sem' = sem vínculo, ou o id
  const [filtroPapel, setFiltroPapel] = useState<PapelVinculo | ''>('')
  const [filtroTipo, setFiltroTipo] = useState<TipoPessoa | ''>('')
  const [edicao, setEdicao] = useState<Edicao>(null)

  const nomeNegocio = useMemo(() => new Map((negocios.data ?? []).map((n) => [n.id, n.nome])), [negocios.data])
  // vínculos ativos por pessoa: a lista tem centenas de linhas, então o índice evita varrer tudo a cada render
  const vinculosPorPessoa = useMemo(() => {
    const m = new Map<string, Vinculo[]>()
    for (const v of vinculos.data ?? []) {
      if (!v.ativo) continue
      const atual = m.get(v.pessoa_id)
      if (atual) atual.push(v); else m.set(v.pessoa_id, [v])
    }
    return m
  }, [vinculos.data])
  const vinculosDe = (id: string) => vinculosPorPessoa.get(id) ?? []
  const termo = busca.trim().toLowerCase()
  const digitos = somenteDigitos(busca)
  const lista = (pessoas.data ?? []).filter((p) => {
    if (!mostrarInativas && !p.ativo) return false
    if (filtroTipo && p.tipo !== filtroTipo) return false
    const vs = vinculosDe(p.id)
    if (filtroNegocio === 'sem' ? vs.length > 0 : filtroNegocio && !vs.some((v) => v.negocio_id === filtroNegocio)) return false
    if (filtroPapel && !vs.some((v) => v.papel === filtroPapel)) return false
    if (!termo) return true
    return p.nome.toLowerCase().includes(termo)
      || (digitos.length > 0 && (p.documento ?? '').includes(digitos))
      || (p.email ?? '').includes(termo)
      || (p.login_servidor ?? '').toLowerCase().includes(termo)
  })
  const totalInativas = (pessoas.data ?? []).filter((p) => !p.ativo).length
  const temFiltro = Boolean(termo || filtroNegocio || filtroPapel || filtroTipo)
  const pessoaEmEdicao = edicao?.modo === 'editar' ? (pessoas.data ?? []).find((p) => p.id === edicao.pessoaId) : undefined

  function fechar() { criar.reset(); atualizar.reset(); excluir.reset(); setEdicao(null) }
  function salvar(dados: DadosPessoa) {
    if (!edicao) return
    if (edicao.modo === 'nova') criar.mutate(dados, { onSuccess: (p) => setEdicao({ modo: 'editar', pessoaId: p.id }) })
    else atualizar.mutate({ id: edicao.pessoaId, ...dados }, { onSuccess: fechar })
  }
  const erroSalvar = criar.error ?? atualizar.error ?? excluir.error
  const carregando = pessoas.isPending || vinculos.isPending || negocios.isPending
  const erroCarga = pessoas.error ?? vinculos.error ?? negocios.error

  return (
    <>
      <CabecalhoPagina titulo="Pessoas" descricao="Clientes, fornecedores e contatos, com vínculos por negócio" acoes={<Botao onClick={() => setEdicao({ modo: 'nova' })}>Nova pessoa</Botao>} />
      {carregando && <Carregando texto="Carregando pessoas…" />}
      {erroCarga && <Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(erroCarga)}</Alerta>}
      {alternarAtivo.error != null && <Alerta tipo="erro">{mensagemDeErro(alternarAtivo.error)}</Alerta>}
      {pessoas.isSuccess && vinculos.isSuccess && negocios.isSuccess && (
        <Cartao className="p-0">
          <div className="flex flex-wrap items-center gap-3 border-b border-line px-6 py-3 text-sm">
            <input type="search" aria-label="Buscar por nome, documento, e-mail ou login" placeholder="Buscar por nome, CPF/CNPJ, e-mail ou login" value={busca} onChange={(e) => setBusca(e.target.value)} className="h-9 w-full max-w-sm rounded-md border border-line bg-white px-3 text-sm outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-100" />
            {(negocios.data ?? []).length > 0 && (
              <select aria-label="Filtrar por negócio" value={filtroNegocio} onChange={(e) => setFiltroNegocio(e.target.value)} className="h-9 rounded-md border border-line bg-white px-2 text-sm">
                <option value="">Todos os negócios</option>
                {(negocios.data ?? []).filter((n) => n.ativo).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
                <option value="sem">Sem vínculo</option>
              </select>
            )}
            <select aria-label="Filtrar por papel" value={filtroPapel} onChange={(e) => setFiltroPapel(e.target.value as PapelVinculo | '')} className="h-9 rounded-md border border-line bg-white px-2 text-sm">
              <option value="">Todos os papéis</option>
              {PAPEIS_VINCULO.map((p) => <option key={p.valor} value={p.valor}>{p.rotulo}</option>)}
            </select>
            <select aria-label="Filtrar por tipo de pessoa" value={filtroTipo} onChange={(e) => setFiltroTipo(e.target.value as TipoPessoa | '')} className="h-9 rounded-md border border-line bg-white px-2 text-sm">
              <option value="">Física e jurídica</option>
              {TIPOS_PESSOA.map((t) => <option key={t.valor} value={t.valor}>{t.rotulo}</option>)}
            </select>
            <span className="text-ink-muted">{lista.length} {lista.length === 1 ? 'pessoa' : 'pessoas'}</span>
            {totalInativas > 0 && (
              <label className="ml-auto flex items-center gap-2">
                <input type="checkbox" checked={mostrarInativas} onChange={(e) => setMostrarInativas(e.target.checked)} className="size-4 accent-brand-600" />
                Mostrar inativas ({totalInativas})
              </label>
            )}
          </div>
          {lista.length === 0 ? (
            <div className="flex flex-col items-center gap-3 py-16 text-center">
              <p className="text-sm font-medium">{temFiltro ? "Nenhuma pessoa encontrada" : "Nenhuma pessoa cadastrada"}</p>
              {!temFiltro && <Botao onClick={() => setEdicao({ modo: "nova" })}>Nova pessoa</Botao>}
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                  <tr className="border-b border-line">
                    <th className="px-6 py-3 font-medium">Nome</th>
                    <th className="px-6 py-3 font-medium">Documento</th>
                    <th className="px-6 py-3 font-medium">Contato</th>
                    <th className="px-6 py-3 font-medium">Vínculos</th>
                    <th className="px-6 py-3 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {lista.map((p) => (
                    <tr key={p.id} onClick={() => setEdicao({ modo: 'editar', pessoaId: p.id })} className="cursor-pointer border-b border-line last:border-0 hover:bg-surface">
                      <td className="px-6 py-3"><div className="font-medium">{p.nome}</div><div className="text-xs text-ink-muted">{p.tipo === 'fisica' ? 'Pessoa física' : 'Pessoa jurídica'}</div></td>
                      <td className="px-6 py-3 tabular-nums text-ink-muted">{formatarDocumento(p.documento)}</td>
                      <td className="px-6 py-3 text-ink-muted"><div>{p.email ?? ''}</div><div className="text-xs">{formatarTelefone(p.telefone)}</div></td>
                      <td className="px-6 py-3">
                        <div className="flex flex-wrap gap-1">
                          {vinculosDe(p.id).length === 0 ? <span className="text-xs text-ink-muted">—</span> : vinculosDe(p.id).map((v) => (
                            <Distintivo key={v.id} tom="info">{`${nomeNegocio.get(v.negocio_id) ?? '—'} · ${ROTULO_PAPEL[v.papel]}`}</Distintivo>
                          ))}
                        </div>
                      </td>
                      <td className="px-6 py-3">
                        <div className="flex items-center gap-2">
                          <Distintivo tom={p.ativo ? 'ok' : 'neutro'}>{p.ativo ? 'Ativa' : 'Inativa'}</Distintivo>
                          <button type="button" className="text-xs font-medium text-brand-700 hover:underline disabled:opacity-50"
                            disabled={alternarAtivo.isPending}
                            onClick={(e) => { e.stopPropagation(); alternarAtivo.mutate({ id: p.id, ativo: !p.ativo }) }}>
                            {p.ativo ? 'Desativar' : 'Ativar'}
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Cartao>
      )}
      <Modal aberto={edicao !== null} aoFechar={fechar} titulo={edicao?.modo === 'editar' ? 'Editar pessoa' : 'Nova pessoa'}>
        {edicao && (edicao.modo === 'nova' || pessoaEmEdicao) && (
          <div className="space-y-4">
            <FormularioPessoa
              key={edicao.modo === 'editar' ? edicao.pessoaId : 'nova'}
              pessoa={pessoaEmEdicao}
              salvando={criar.isPending || atualizar.isPending}
              excluindo={excluir.isPending}
              erro={erroSalvar ? mensagemDeErro(erroSalvar) : null}
              aoSalvar={salvar}
              aoCancelar={fechar}
              aoExcluir={edicao.modo === 'editar' ? () => excluir.mutate(edicao.pessoaId, { onSuccess: fechar }) : undefined}
            />
            {pessoaEmEdicao && <VinculosPessoa pessoa={pessoaEmEdicao} vinculos={vinculos.data ?? []} negocios={negocios.data ?? []} />}
          </div>
        )}
      </Modal>
    </>
  )
}
