import { useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { useAtualizarCategoria, useCategorias, useCriarCategoria } from '../api'
import { FormularioCategoria } from '../components/FormularioCategoria'
import { montarArvore, TIPOS_CATEGORIA, type Categoria, type DadosCategoria, type TipoCategoria } from '../tipos'

type Edicao = { modo: 'nova'; paiId?: string } | { modo: 'editar'; categoria: Categoria } | null

export function CategoriasPage() {
  const categorias = useCategorias()
  const criar = useCriarCategoria()
  const atualizar = useAtualizarCategoria()
  const [tipo, setTipo] = useState<TipoCategoria>('despesa')
  const [mostrarInativas, setMostrarInativas] = useState(false)
  const [edicao, setEdicao] = useState<Edicao>(null)

  const todas = categorias.data ?? []
  const doTipo = todas.filter((c) => c.tipo === tipo)
  const visiveis = doTipo.filter((c) => mostrarInativas || c.ativo)
  const arvore = montarArvore(visiveis)
  const totalInativas = doTipo.filter((c) => !c.ativo).length

  function fechar() {
    criar.reset()
    atualizar.reset()
    setEdicao(null)
  }

  function salvar(dados: DadosCategoria) {
    if (!edicao) return
    if (edicao.modo === 'nova') criar.mutate(dados, { onSuccess: fechar })
    else {
      const { tipo: _tipo, ...semTipo } = dados
      atualizar.mutate({ id: edicao.categoria.id, ...semTipo }, { onSuccess: fechar })
    }
  }

  const erroSalvar = criar.error ?? atualizar.error

  function Linha({ c, sub }: { c: Categoria; sub?: boolean }) {
    return (
      <li>
        <button
          type="button"
          onClick={() => setEdicao({ modo: 'editar', categoria: c })}
          className={`flex w-full items-center justify-between gap-3 px-6 py-2.5 text-left text-sm hover:bg-surface ${sub ? 'pl-12' : ''}`}
        >
          <span className="flex items-center gap-2">
            {sub && <span className="text-ink-muted" aria-hidden="true">└</span>}
            <span className={sub ? '' : 'font-medium'}>{c.nome}</span>
          </span>
          <span className="flex items-center gap-3">
            {!c.ativo && <Distintivo tom="neutro">Inativa</Distintivo>}
            {!sub && c.ativo && (
              <span
                role="button"
                tabIndex={0}
                onClick={(e) => { e.stopPropagation(); setEdicao({ modo: 'nova', paiId: c.id }) }}
                onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); setEdicao({ modo: 'nova', paiId: c.id }) } }}
                className="rounded px-2 py-0.5 text-xs text-brand-600 hover:bg-brand-50"
              >
                + subcategoria
              </span>
            )}
          </span>
        </button>
      </li>
    )
  }

  return (
    <>
      <CabecalhoPagina
        titulo="Categorias"
        descricao="Classificação de receitas e despesas, com subcategorias"
        acoes={<Botao onClick={() => setEdicao({ modo: 'nova' })}>Nova categoria</Botao>}
      />

      {categorias.isPending && <Carregando texto="Carregando categorias…" />}

      {categorias.isError && (
        <Alerta tipo="erro" titulo="Não foi possível carregar as categorias">
          {mensagemDeErro(categorias.error)}
          <div className="mt-2"><Botao variante="secundario" onClick={() => categorias.refetch()}>Tentar novamente</Botao></div>
        </Alerta>
      )}

      {categorias.isSuccess && (
        <Cartao className="p-0">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-line px-6 py-3 text-sm">
            <div role="tablist" aria-label="Filtrar por tipo" className="flex rounded-md border border-line p-0.5">
              {TIPOS_CATEGORIA.map((t) => (
                <button
                  key={t.valor}
                  role="tab"
                  aria-selected={tipo === t.valor}
                  onClick={() => setTipo(t.valor)}
                  className={`rounded px-3 py-1 text-sm ${tipo === t.valor ? 'bg-brand-600 text-white' : 'text-ink-muted hover:text-ink'}`}
                >
                  {t.rotulo}s
                </button>
              ))}
            </div>
            <div className="flex items-center gap-4">
              <span className="text-ink-muted">{visiveis.length} {visiveis.length === 1 ? 'categoria' : 'categorias'}</span>
              {totalInativas > 0 && (
                <label className="flex items-center gap-2">
                  <input type="checkbox" checked={mostrarInativas} onChange={(e) => setMostrarInativas(e.target.checked)} className="size-4 accent-brand-600" />
                  Mostrar inativas ({totalInativas})
                </label>
              )}
            </div>
          </div>

          {arvore.length === 0 ? (
            <div className="flex flex-col items-center gap-3 py-16 text-center">
              <p className="text-sm font-medium">Nenhuma categoria de {tipo} cadastrada</p>
              <Botao onClick={() => setEdicao({ modo: 'nova' })}>Nova categoria</Botao>
            </div>
          ) : (
            <ul className="divide-y divide-line">
              {arvore.map(({ raiz, filhas }) => (
                <li key={raiz.id}>
                  <ul>
                    <Linha c={raiz} />
                    {filhas.map((f) => <Linha key={f.id} c={f} sub />)}
                  </ul>
                </li>
              ))}
            </ul>
          )}
        </Cartao>
      )}

      <Modal aberto={edicao !== null} aoFechar={fechar} titulo={edicao?.modo === 'editar' ? 'Editar categoria' : 'Nova categoria'}>
        {edicao && (
          <FormularioCategoria
            key={edicao.modo === 'editar' ? edicao.categoria.id : `nova-${edicao.paiId ?? ''}`}
            categoria={edicao.modo === 'editar' ? edicao.categoria : undefined}
            todas={todas}
            tipoInicial={tipo}
            paiInicial={edicao.modo === 'nova' ? edicao.paiId ?? null : null}
            salvando={criar.isPending || atualizar.isPending}
            erro={erroSalvar ? mensagemDeErro(erroSalvar) : null}
            aoSalvar={salvar}
            aoCancelar={fechar}
          />
        )}
      </Modal>
    </>
  )
}
