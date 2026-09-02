import { useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Modal } from '../../../core/ui/Modal'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData, formatarMoeda } from '../../../core/formatos'
import { useAtualizarConta, useContas, useCriarConta } from '../api'
import { FormularioConta } from '../components/FormularioConta'
import { ROTULO_TIPO, type Conta, type DadosConta } from '../tipos'
import { useNegocios } from '../../negocios/api'
import { ROTULO_PESSOAL } from '../../negocios/tipos'

type Edicao = { modo: 'nova' } | { modo: 'editar'; conta: Conta } | null

export function ContasPage() {
  const contas = useContas()
  const negocios = useNegocios()
  const nomeNegocio = new Map((negocios.data ?? []).map((n) => [n.id, n.nome]))
  const criar = useCriarConta()
  const atualizar = useAtualizarConta()
  const [edicao, setEdicao] = useState<Edicao>(null)
  const [mostrarInativas, setMostrarInativas] = useState(false)

  const lista = (contas.data ?? []).filter((c) => mostrarInativas || c.ativo)
  const totalInativas = (contas.data ?? []).filter((c) => !c.ativo).length

  function fechar() {
    criar.reset()
    atualizar.reset()
    setEdicao(null)
  }

  function salvar(dados: DadosConta) {
    if (!edicao) return
    if (edicao.modo === 'nova') criar.mutate(dados, { onSuccess: fechar })
    else {
      const { tipo: _tipo, ...semTipo } = dados
      atualizar.mutate({ id: edicao.conta.id, ...semTipo }, { onSuccess: fechar })
    }
  }

  const erroSalvar = criar.error ?? atualizar.error

  return (
    <>
      <CabecalhoPagina
        titulo="Contas"
        descricao="Contas bancárias, dinheiro, carteiras e investimentos"
        acoes={<Botao onClick={() => setEdicao({ modo: 'nova' })}>Nova conta</Botao>}
      />

      {contas.isPending && <Carregando texto="Carregando contas…" />}

      {contas.isError && (
        <Alerta tipo="erro" titulo="Não foi possível carregar as contas">
          {mensagemDeErro(contas.error)}
          <div className="mt-2"><Botao variante="secundario" onClick={() => contas.refetch()}>Tentar novamente</Botao></div>
        </Alerta>
      )}

      {contas.isSuccess && (
        <Cartao className="p-0">
          <div className="flex items-center justify-between border-b border-line px-6 py-3 text-sm">
            <span className="text-ink-muted">{lista.length} {lista.length === 1 ? 'conta' : 'contas'}</span>
            {totalInativas > 0 && (
              <label className="flex items-center gap-2">
                <input type="checkbox" checked={mostrarInativas} onChange={(e) => setMostrarInativas(e.target.checked)} className="size-4 accent-brand-600" />
                Mostrar inativas ({totalInativas})
              </label>
            )}
          </div>

          {lista.length === 0 ? (
            <div className="flex flex-col items-center gap-3 py-16 text-center">
              <p className="text-sm font-medium">Nenhuma conta cadastrada</p>
              <p className="max-w-sm text-sm text-ink-muted">Cadastre suas contas bancárias, dinheiro em espécie e carteiras para começar a registrar lançamentos.</p>
              <Botao onClick={() => setEdicao({ modo: 'nova' })}>Nova conta</Botao>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs uppercase tracking-wide text-ink-muted">
                  <tr className="border-b border-line">
                    <th className="px-6 py-3 font-medium">Nome</th>
                    <th className="px-6 py-3 font-medium">Tipo</th>
                    <th className="px-6 py-3 font-medium">Negócio</th>
                    <th className="px-6 py-3 text-right font-medium">Saldo inicial</th>
                    <th className="px-6 py-3 text-right font-medium">Saldo atual</th>
                    <th className="px-6 py-3 font-medium">Início</th>
                    <th className="px-6 py-3 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {lista.map((c) => (
                    <tr
                      key={c.id}
                      onClick={() => setEdicao({ modo: 'editar', conta: c })}
                      className="cursor-pointer border-b border-line last:border-0 hover:bg-surface"
                    >
                      <td className="px-6 py-3 font-medium">{c.nome}</td>
                      <td className="px-6 py-3 text-ink-muted">{ROTULO_TIPO[c.tipo]}</td>
                      <td className="px-6 py-3 text-ink-muted">{c.negocio_id ? nomeNegocio.get(c.negocio_id) ?? '—' : ROTULO_PESSOAL}</td>
                      <td className="px-6 py-3 text-right tabular-nums text-ink-muted">{formatarMoeda(c.saldo_inicial)}</td>
                      <td className={`px-6 py-3 text-right font-medium tabular-nums ${c.saldo < 0 ? 'text-red-700' : ''}`}>{formatarMoeda(c.saldo)}</td>
                      <td className="px-6 py-3 text-ink-muted tabular-nums">{formatarData(c.data_inicio)}</td>
                      <td className="px-6 py-3"><Distintivo tom={c.ativo ? 'ok' : 'neutro'}>{c.ativo ? 'Ativa' : 'Inativa'}</Distintivo></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Cartao>
      )}

      <Modal aberto={edicao !== null} aoFechar={fechar} titulo={edicao?.modo === 'editar' ? 'Editar conta' : 'Nova conta'}>
        {edicao && (
          <FormularioConta
            key={edicao.modo === 'editar' ? edicao.conta.id : 'nova'}
            conta={edicao.modo === 'editar' ? edicao.conta : undefined}
            negocios={negocios.data ?? []}
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
