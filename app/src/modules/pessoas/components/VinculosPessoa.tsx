import { useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Selecao } from '../../../core/ui/Selecao'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import type { Negocio } from '../../negocios/tipos'
import { useAtualizarVinculo, useCriarVinculo } from '../api'
import { PAPEIS_VINCULO, ROTULO_PAPEL, type PapelVinculo, type Pessoa, type Vinculo } from '../tipos'

interface Props { pessoa: Pessoa; vinculos: Vinculo[]; negocios: Negocio[] }

/** Vínculos da pessoa com negócios: lista com ativar/inativar e formulário de novo vínculo. */
export function VinculosPessoa({ pessoa, vinculos, negocios }: Props) {
  const criar = useCriarVinculo()
  const atualizar = useAtualizarVinculo()
  const [negocioId, setNegocioId] = useState('')
  const [papel, setPapel] = useState<PapelVinculo>('cliente')
  const nomeNegocio = new Map(negocios.map((n) => [n.id, n.nome]))
  const ativos = negocios.filter((n) => n.ativo)
  const meus = vinculos.filter((v) => v.pessoa_id === pessoa.id)
  const erro = criar.error ?? atualizar.error

  function vincular() {
    if (!negocioId) return
    criar.mutate({ pessoa_id: pessoa.id, negocio_id: negocioId, papel }, { onSuccess: () => setNegocioId('') })
  }

  return (
    <div className="space-y-3 border-t border-line pt-4">
      <h3 className="text-sm font-semibold">Vínculos com negócios</h3>
      {erro && <Alerta tipo="erro">{mensagemDeErro(erro)}</Alerta>}
      {meus.length === 0
        ? <p className="text-sm text-ink-muted">Nenhum vínculo. Vincule esta pessoa a um negócio para usá-la em contratos e lançamentos daquele negócio.</p>
        : (
          <ul className="divide-y divide-line rounded-md border border-line">
            {meus.map((v) => (
              <li key={v.id} className="flex items-center justify-between gap-3 px-3 py-2 text-sm">
                <span><span className="font-medium">{nomeNegocio.get(v.negocio_id) ?? '—'}</span> <span className="text-ink-muted">· {ROTULO_PAPEL[v.papel]}</span></span>
                <span className="flex items-center gap-2">
                  <Distintivo tom={v.ativo ? 'ok' : 'neutro'}>{v.ativo ? 'Ativo' : 'Inativo'}</Distintivo>
                  <button type="button" className="text-xs text-brand-600 hover:underline" disabled={atualizar.isPending} onClick={() => atualizar.mutate({ id: v.id, ativo: !v.ativo })}>
                    {v.ativo ? 'Inativar' : 'Reativar'}
                  </button>
                </span>
              </li>
            ))}
          </ul>
        )}
      {ativos.length === 0
        ? <p className="text-xs text-ink-muted">Cadastre um negócio ativo para criar vínculos.</p>
        : (
          <div className="grid grid-cols-[1fr_1fr_auto] items-end gap-2">
            <Selecao rotulo="Negócio" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...ativos.map((n) => ({ valor: n.id, rotulo: n.nome }))]} value={negocioId} onChange={(e) => setNegocioId(e.target.value)} />
            <Selecao rotulo="Papel" opcoes={PAPEIS_VINCULO} value={papel} onChange={(e) => setPapel(e.target.value as PapelVinculo)} />
            <Botao type="button" variante="secundario" onClick={vincular} carregando={criar.isPending} disabled={!negocioId || !pessoa.ativo}>Vincular</Botao>
          </div>
        )}
    </div>
  )
}
