import { Link } from 'react-router'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Alerta } from '../../../core/ui/Alerta'
import { Carregando } from '../../../core/ui/Carregando'
import { Distintivo } from '../../../core/ui/Distintivo'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { usePessoas } from '../../pessoas/api'
import { formatarTelefone } from '../../pessoas/tipos'
import { useCancelarIndicacao, useIndicacoesAdmin } from '../../portal/api'

const linkWhatsApp = (numero: string, texto: string) => `https://wa.me/${numero.replace(/\D/g, '')}?text=${encodeURIComponent(texto)}`

/**
 * Vitrine de quem chegou e ainda não virou cliente: hoje isso é só a fila de
 * indicações pendentes (Indique e Ganhe). Contato vindo direto do site ainda
 * não existe no ERP — quando quiser isso, é outra etapa (formulário público +
 * onde guardar sem virar porta pra spam). Ação real (converter/cancelar) fica
 * em Indicações; aqui é o atalho pra ver rápido e chamar no WhatsApp.
 */
export function NovidadesPage() {
  const negocios = useNegocios()
  const indicacoes = useIndicacoesAdmin()
  const pessoas = usePessoas()
  const cancelar = useCancelarIndicacao()

  const nomeNegocio = new Map((negocios.data ?? []).map((n) => [n.id, n.nome]))
  const nomePessoa = new Map((pessoas.data ?? []).map((p) => [p.id, p.nome]))
  const pendentes = (indicacoes.data ?? [])
    .filter((i) => i.status === 'pendente')
    .sort((a, b) => b.criado_em.localeCompare(a.criado_em))

  const carregando = negocios.isPending || indicacoes.isPending || pessoas.isPending
  const erro = negocios.error ?? indicacoes.error ?? pessoas.error

  return (
    <>
      <CabecalhoPagina titulo="Novidades" descricao="Indicados aguardando contato — quem chegou e ainda não virou cliente" />

      <Alerta tipo="info">
        Hoje isso mostra as <b>indicações do Indique e Ganhe</b> ainda aguardando conversão. Contato vindo direto do site ainda não existe no ERP —
        se quiser um formulário público captando lead, é uma etapa nova pra planejarmos.
      </Alerta>

      <div className="mt-4">
        {carregando && <Carregando texto="Carregando…" />}
        {erro && <Alerta tipo="erro" titulo="Não foi possível carregar">{mensagemDeErro(erro)}</Alerta>}
        {cancelar.error && <div className="mb-3"><Alerta tipo="erro">{mensagemDeErro(cancelar.error)}</Alerta></div>}

        {!carregando && !erro && (
          <Cartao className="p-0">
            {pendentes.length === 0 ? (
              <p className="px-6 py-14 text-center text-sm text-ink-muted">Nenhum indicado aguardando contato no momento.</p>
            ) : (
              <ul className="divide-y divide-line">
                {pendentes.map((i) => (
                  <li key={i.id} className="flex flex-wrap items-center justify-between gap-3 px-6 py-4">
                    <div className="min-w-0">
                      <p className="font-medium">
                        {i.nome_indicado} <span className="font-normal text-ink-muted">{formatarTelefone(i.telefone_indicado)}</span>
                        <span className="ml-2"><Distintivo tom="info">Aguardando</Distintivo></span>
                      </p>
                      <p className="mt-0.5 text-xs text-ink-muted">
                        Indicado por {nomePessoa.get(i.indicador_pessoa_id) ?? '—'} · {nomeNegocio.get(i.negocio_id) ?? '—'} · {formatarData(i.criado_em.slice(0, 10))}
                      </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                      <a href={linkWhatsApp(i.telefone_indicado, `Olá, ${i.nome_indicado}! Tudo bem? Vi que você foi indicado(a) pra gente — vamos conversar?`)}
                        target="_blank" rel="noreferrer"
                        className="inline-flex h-9 items-center rounded-md bg-green-600 px-3 text-sm font-medium text-white hover:bg-green-700">
                        WhatsApp
                      </a>
                      <Link to="/indicacoes" className="text-xs font-medium text-brand-700 hover:underline">Converter</Link>
                      <button type="button" className="text-xs text-ink-muted hover:underline"
                        onClick={() => cancelar.mutate({ id: i.id, observacao: 'Cancelada pelo administrador' })}>
                        descartar
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
            <p className="border-t border-line px-6 py-3 text-xs text-ink-muted">
              Converter (virar cliente de verdade) é feito em <Link to="/indicacoes" className="text-brand-700 hover:underline">Indicações</Link>, junto do presente da campanha.
            </p>
          </Cartao>
        )}
      </div>
    </>
  )
}
