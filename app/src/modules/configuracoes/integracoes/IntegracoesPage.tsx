import { useState } from 'react'
import { CabecalhoPagina } from '../../../core/ui/CabecalhoPagina'
import { Cartao } from '../../../core/ui/Cartao'
import { Botao } from '../../../core/ui/Botao'
import { Alerta } from '../../../core/ui/Alerta'
import { Campo } from '../../../core/ui/Campo'
import { Selecao } from '../../../core/ui/Selecao'
import { Carregando } from '../../../core/ui/Carregando'
import { Distintivo } from '../../../core/ui/Distintivo'
import { Modal } from '../../../core/ui/Modal'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import { formatarData } from '../../../core/formatos'
import { useNegocios } from '../../negocios/api'
import { useApiTokens, useCriarApiToken, useRevogarApiToken } from './api'

const URL_FUNCAO = `${String(import.meta.env.VITE_SUPABASE_URL ?? '')}/functions/v1/api-consulta-cliente`

/** Endpoint pronto pra copiar/colar na documentação de quem for integrar. */
function ExemploRequisicao() {
  const exemplo = `POST ${URL_FUNCAO}
Content-Type: application/json
Token: <o token gerado abaixo>

{"cpf_cnpj": "12345678901"}`
  return (
    <pre className="mt-2 overflow-x-auto rounded-md bg-ink px-4 py-3 text-xs text-white/90"><code>{exemplo}</code></pre>
  )
}

export function IntegracoesPage() {
  const negocios = useNegocios()
  const tokens = useApiTokens()
  const criar = useCriarApiToken()
  const revogar = useRevogarApiToken()

  const [modal, setModal] = useState(false)
  const [negocioId, setNegocioId] = useState('')
  const [nome, setNome] = useState('')
  const [gerado, setGerado] = useState<{ token: string; nome: string } | null>(null)
  const [copiado, setCopiado] = useState(false)

  const ativos = (negocios.data ?? []).filter((n) => n.ativo)

  function fechar() {
    setModal(false); setNegocioId(''); setNome(''); setGerado(null); setCopiado(false); criar.reset()
  }

  async function copiar(texto: string) {
    try { await navigator.clipboard.writeText(texto); setCopiado(true) } catch { /* clipboard indisponível */ }
  }

  return (
    <>
      <CabecalhoPagina titulo="Integrações via API" descricao="Sistemas de fora consultando dados de cliente pelo token — hoje: Leveduca" />

      <Alerta tipo="info">
        Cada token dá acesso a consultar, por CPF/CNPJ, se a pessoa é cliente ativo de um negócio específico (nome, e-mail, plano e status) —
        nada de financeiro. O valor do token só aparece <b>uma vez</b>, na hora de gerar; se perder, revogue e gere outro.
      </Alerta>

      <Cartao className="mt-4">
        <h2 className="mb-1 text-sm font-semibold uppercase tracking-wide text-ink-muted">Endpoint</h2>
        <p className="text-sm text-ink-muted">Envie o CPF/CNPJ e receba os dados do cliente. Repasse isto pra quem for integrar:</p>
        <ExemploRequisicao />
      </Cartao>

      <Cartao className="mt-4 p-0">
        <div className="flex items-center justify-between border-b border-line px-6 py-4">
          <h2 className="text-sm font-semibold">Tokens gerados</h2>
          <Botao onClick={() => setModal(true)} disabled={ativos.length === 0}>Novo token</Botao>
        </div>
        {ativos.length === 0 && <p className="px-6 py-4 text-sm text-ink-muted">Cadastre um negócio ativo antes.</p>}
        {tokens.isPending ? <Carregando /> : tokens.error ? <div className="p-4"><Alerta tipo="erro">{mensagemDeErro(tokens.error)}</Alerta></div> : (
          (tokens.data ?? []).length === 0 ? (
            <p className="px-6 py-10 text-center text-sm text-ink-muted">Nenhum token gerado ainda.</p>
          ) : (
            <ul className="divide-y divide-line">
              {(tokens.data ?? []).map((t) => (
                <li key={t.id} className="flex flex-wrap items-center justify-between gap-3 px-6 py-4">
                  <div className="min-w-0">
                    <p className="font-medium">
                      {t.nome} <span className="ml-2 font-mono text-xs text-ink-muted">{t.token_prefixo}…</span>
                      <span className="ml-2"><Distintivo tom={t.ativo ? 'ok' : 'neutro'}>{t.ativo ? 'Ativo' : 'Revogado'}</Distintivo></span>
                    </p>
                    <p className="mt-0.5 text-xs text-ink-muted">
                      {t.negocio} · criado em {formatarData(t.criado_em.slice(0, 10))} · {t.consultas} consulta(s)
                      {t.ultimo_uso_em && ` · última em ${formatarData(t.ultimo_uso_em.slice(0, 10))}`}
                    </p>
                  </div>
                  {t.ativo && (
                    <button type="button" className="shrink-0 text-xs text-red-700 hover:underline" disabled={revogar.isPending}
                      onClick={() => { if (window.confirm(`Revogar o token "${t.nome}"? Quem estiver usando perde o acesso na hora.`)) revogar.mutate(t.id) }}>
                      revogar
                    </button>
                  )}
                </li>
              ))}
            </ul>
          )
        )}
      </Cartao>

      <Modal aberto={modal} aoFechar={fechar} titulo={gerado ? 'Token gerado' : 'Novo token de integração'}>
        {gerado ? (
          <div className="space-y-4">
            <Alerta tipo="info" titulo="Copie agora — não vai aparecer de novo">
              Esse é o único momento em que o valor completo do token é mostrado.
            </Alerta>
            <div>
              <p className="mb-1 text-sm font-medium">{gerado.nome}</p>
              <div className="flex items-center gap-2">
                <code className="flex-1 overflow-x-auto rounded-md border border-line bg-surface px-3 py-2 text-xs">{gerado.token}</code>
                <Botao variante="secundario" onClick={() => void copiar(gerado.token)}>{copiado ? 'Copiado!' : 'Copiar'}</Botao>
              </div>
            </div>
            <div className="flex justify-end"><Botao onClick={fechar}>Fechar</Botao></div>
          </div>
        ) : (
          <div className="space-y-4">
            {criar.error && <Alerta tipo="erro">{mensagemDeErro(criar.error)}</Alerta>}
            <Campo rotulo="Nome do token (pra você reconhecer depois)" value={nome} onChange={(e) => setNome(e.target.value)} maxLength={60} placeholder="Ex.: Leveduca" autoFocus />
            <Selecao rotulo="Negócio" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...ativos.map((n) => ({ valor: n.id, rotulo: n.nome }))]} value={negocioId} onChange={(e) => setNegocioId(e.target.value)} />
            <div className="flex justify-end gap-2">
              <Botao variante="secundario" onClick={fechar} disabled={criar.isPending}>Cancelar</Botao>
              <Botao
                disabled={!negocioId || nome.trim().length < 2}
                carregando={criar.isPending}
                onClick={() => criar.mutate({ negocio_id: negocioId, nome: nome.trim() }, { onSuccess: (r) => setGerado({ token: r.token, nome: nome.trim() }) })}
              >
                Gerar token
              </Botao>
            </div>
          </div>
        )}
      </Modal>
    </>
  )
}
