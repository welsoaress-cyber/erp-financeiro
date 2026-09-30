import { useMemo, useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { BarraFiltros, CampoBusca, ContagemFiltro, SelectFiltro } from '../../../core/ui/Filtros'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { useContas } from '../../contas/api'
import { useCentrosCusto } from '../../centros_custo/api'
import { useAtualizarFuncionario, useCriarFuncionario, useFuncionarios } from '../api'
import { FormularioFuncionario } from '../components/FormularioFuncionario'
import { DetalheFuncionario } from '../components/DetalheFuncionario'
import type { Funcionario } from '../tipos'

type Edicao = { modo: 'novo' } | { modo: 'ver'; id: string } | null

export function RhPage() {
  const funcionarios = useFuncionarios()
  const negocios = useNegocios()
  const pessoas = usePessoas()
  const contas = useContas()
  const centros = useCentrosCusto()
  const criar = useCriarFuncionario()
  const atualizar = useAtualizarFuncionario()

  const [edicao, setEdicao] = useState<Edicao>(null)
  const [busca, setBusca] = useState('')
  const [filtroNegocio, setFiltroNegocio] = useState('')
  const [mostrarInativos, setMostrarInativos] = useState(false)

  const nomeNegocio = useMemo(() => new Map((negocios.data ?? []).map((n) => [n.id, n.nome])), [negocios.data])
  const nomePessoa = useMemo(() => new Map((pessoas.data ?? []).map((p) => [p.id, p.nome])), [pessoas.data])

  const termo = busca.trim().toLowerCase()
  const base = funcionarios.data ?? []
  const lista = base.filter((f) => {
    if (!mostrarInativos && !f.ativo) return false
    if (filtroNegocio && f.negocio_id !== filtroNegocio) return false
    if (!termo) return true
    const nome = (nomePessoa.get(f.pessoa_id) ?? '').toLowerCase()
    return nome.includes(termo) || (f.cargo ?? '').toLowerCase().includes(termo) || (f.departamento ?? '').toLowerCase().includes(termo)
  })
  const funcionarioVisto = edicao?.modo === 'ver' ? base.find((f) => f.id === edicao.id) : undefined
  const totalInativos = base.filter((f) => !f.ativo).length

  function fechar() { criar.reset(); atualizar.reset(); setEdicao(null) }

  const carregando = funcionarios.isPending || negocios.isPending || pessoas.isPending
  const erro = funcionarios.error ?? negocios.error ?? pessoas.error

  return (
    <>
      <CabecalhoPagina titulo="RH" descricao="Funcionários, ponto informal, férias e folha simplificada" acoes={<Botao onClick={() => setEdicao({ modo: 'novo' })}>Novo funcionário</Botao>} />
      {carregando && <Carregando texto="Carregando funcionários…" />}
      {erro && <Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(erro)}</Alerta>}

      {funcionarios.isSuccess && negocios.isSuccess && pessoas.isSuccess && (
        <Cartao className="p-0">
          <BarraFiltros>
            <CampoBusca valor={busca} aoMudar={setBusca} rotulo="Buscar por nome, cargo ou departamento" />
            <ContagemFiltro visiveis={lista.length} total={base.length} singular="funcionário" plural="funcionários" />
            <SelectFiltro valor={filtroNegocio} aoMudar={setFiltroNegocio} rotulo="Filtrar por negócio">
              <option value="">Todos os negócios</option>
              {(negocios.data ?? []).map((n) => <option key={n.id} value={n.id}>{n.nome}</option>)}
            </SelectFiltro>
            {totalInativos > 0 && (
              <label className="ml-auto flex items-center gap-2 text-sm">
                <input type="checkbox" checked={mostrarInativos} onChange={(e) => setMostrarInativos(e.target.checked)} className="size-4 accent-brand-600" />
                Mostrar inativos ({totalInativos})
              </label>
            )}
          </BarraFiltros>
          {lista.length === 0 ? (
            <div className="flex flex-col items-center gap-3 py-16 text-center">
              <p className="text-sm font-medium">Nenhum funcionário cadastrado</p>
              <Botao onClick={() => setEdicao({ modo: 'novo' })}>Novo funcionário</Botao>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                  <tr className="border-b border-line">
                    <th className="px-6 py-3 font-medium">Nome</th>
                    <th className="px-6 py-3 font-medium">Cargo</th>
                    <th className="px-6 py-3 font-medium">Negócio</th>
                    <th className="px-6 py-3 text-right font-medium">Salário base</th>
                    <th className="px-6 py-3 font-medium">Admissão</th>
                    <th className="px-6 py-3 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {lista.map((f: Funcionario) => (
                    <tr key={f.id} onClick={() => setEdicao({ modo: 'ver', id: f.id })} className="cursor-pointer border-b border-line last:border-0 hover:bg-surface">
                      <td className="px-6 py-3 font-medium">{nomePessoa.get(f.pessoa_id) ?? '—'}</td>
                      <td className="px-6 py-3 text-ink-muted">{f.cargo ?? '—'}{f.departamento ? ` · ${f.departamento}` : ''}</td>
                      <td className="px-6 py-3 text-ink-muted">{nomeNegocio.get(f.negocio_id) ?? '—'}</td>
                      <td className="px-6 py-3 text-right tabular-nums">{formatarMoeda(f.salario_base)}</td>
                      <td className="px-6 py-3 text-ink-muted">{formatarData(f.data_admissao)}</td>
                      <td className="px-6 py-3"><Distintivo tom={f.ativo ? 'ok' : 'neutro'}>{f.ativo ? 'Ativo' : 'Inativo'}</Distintivo></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Cartao>
      )}

      <Modal aberto={edicao !== null} aoFechar={fechar} titulo={edicao?.modo === 'novo' ? 'Novo funcionário' : funcionarioVisto ? (nomePessoa.get(funcionarioVisto.pessoa_id) ?? 'Funcionário') : 'Funcionário'} largura="xl">
        {edicao?.modo === 'novo' && (
          <FormularioFuncionario negocios={negocios.data ?? []} pessoas={pessoas.data ?? []} salvando={criar.isPending} erro={criar.error ? mensagemDeErro(criar.error) : null} aoSalvar={(d) => criar.mutate(d, { onSuccess: fechar })} aoCancelar={fechar} />
        )}
        {funcionarioVisto && (
          <div className="space-y-6">
            <FormularioFuncionario negocios={negocios.data ?? []} pessoas={pessoas.data ?? []} funcionario={funcionarioVisto} salvando={atualizar.isPending} erro={atualizar.error ? mensagemDeErro(atualizar.error) : null} aoSalvar={(d) => atualizar.mutate({ id: funcionarioVisto.id, ...d })} aoCancelar={fechar} />
            <div className="border-t border-line pt-4">
              <DetalheFuncionario funcionario={funcionarioVisto} contas={contas.data ?? []} centros={centros.data ?? []} />
            </div>
          </div>
        )}
      </Modal>
    </>
  )
}
