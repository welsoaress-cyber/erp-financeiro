import { useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { useAtualizarNegocio, useCriarNegocio, useNegocios } from '../api'
import { FormularioNegocio } from '../components/FormularioNegocio'
import type { DadosNegocio, Negocio } from '../tipos'
import { PlanosNegocio } from '../../contratos/components/PlanosNegocio'

type Edicao = { modo: 'novo' } | { modo: 'editar'; negocio: Negocio } | null

export function NegociosPage() {
  const negocios = useNegocios()
  const criar = useCriarNegocio()
  const atualizar = useAtualizarNegocio()
  const [edicao, setEdicao] = useState<Edicao>(null)
  const [mostrarInativos, setMostrarInativos] = useState(false)

  const lista = (negocios.data ?? []).filter((n) => mostrarInativos || n.ativo)
  const totalInativos = (negocios.data ?? []).filter((n) => !n.ativo).length

  function fechar() { criar.reset(); atualizar.reset(); setEdicao(null) }
  function salvar(dados: DadosNegocio) {
    if (!edicao) return
    if (edicao.modo === 'novo') criar.mutate(dados, { onSuccess: fechar })
    else atualizar.mutate({ id: edicao.negocio.id, ...dados }, { onSuccess: fechar })
  }
  const erroSalvar = criar.error ?? atualizar.error

  return (
    <>
      <CabecalhoPagina
        titulo="Negócios"
        descricao="Unidades de negócio para separar o financeiro por operação"
        acoes={<Botao onClick={() => setEdicao({ modo: 'novo' })}>Novo negócio</Botao>}
      />
      {negocios.isPending && <Carregando texto="Carregando negócios…" />}
      {negocios.isError && (
        <Alerta tipo="erro" titulo="Não foi possível carregar os negócios">
          {mensagemDeErro(negocios.error)}
          <div className="mt-2"><Botao variante="secundario" onClick={() => negocios.refetch()}>Tentar novamente</Botao></div>
        </Alerta>
      )}
      {negocios.isSuccess && (
        <Cartao className="p-0">
          <div className="flex items-center justify-between border-b border-line px-6 py-3 text-sm">
            <span className="text-ink-muted">{lista.length} {lista.length === 1 ? 'negócio' : 'negócios'}</span>
            {totalInativos > 0 && (
              <label className="flex items-center gap-2">
                <input type="checkbox" checked={mostrarInativos} onChange={(e) => setMostrarInativos(e.target.checked)} className="size-4 accent-brand-600" />
                Mostrar inativos ({totalInativos})
              </label>
            )}
          </div>
          {lista.length === 0 ? (
            <div className="flex flex-col items-center gap-3 py-16 text-center">
              <p className="text-sm font-medium">Nenhum negócio cadastrado</p>
              <p className="max-w-sm text-sm text-ink-muted">Cadastre seus negócios (ex.: SERVNET, SERVIDOR) para enxergar receitas, despesas e resultado por operação. Sem negócio, tudo é tratado como pessoal.</p>
              <Botao onClick={() => setEdicao({ modo: 'novo' })}>Novo negócio</Botao>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                  <tr className="border-b border-line">
                    <th className="px-6 py-3 font-medium">Nome</th>
                    <th className="px-6 py-3 font-medium">Identificador</th>
                    <th className="px-6 py-3 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {lista.map((n) => (
                    <tr key={n.id} onClick={() => setEdicao({ modo: 'editar', negocio: n })} className="cursor-pointer border-b border-line last:border-0 hover:bg-surface">
                      <td className="px-6 py-3 font-medium">{n.nome}</td>
                      <td className="px-6 py-3 font-mono text-xs text-ink-muted">{n.slug}</td>
                      <td className="px-6 py-3"><Distintivo tom={n.ativo ? 'ok' : 'neutro'}>{n.ativo ? 'Ativo' : 'Inativo'}</Distintivo></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Cartao>
      )}
      <Modal aberto={edicao !== null} aoFechar={fechar} titulo={edicao?.modo === 'editar' ? 'Editar negócio' : 'Novo negócio'}>
        {edicao && (
          <div className="space-y-4">
          <FormularioNegocio
            key={edicao.modo === 'editar' ? edicao.negocio.id : 'novo'}
            negocio={edicao.modo === 'editar' ? edicao.negocio : undefined}
            salvando={criar.isPending || atualizar.isPending}
            erro={erroSalvar ? mensagemDeErro(erroSalvar) : null}
            aoSalvar={salvar}
            aoCancelar={fechar}
          />
          {edicao.modo === 'editar' && <PlanosNegocio negocio={edicao.negocio} />}
          </div>
        )}
      </Modal>
    </>
  )
}
