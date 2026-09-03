import { useState, type FormEvent } from 'react'
import { useParams } from 'react-router'
import { Alerta } from '../../core/ui/Alerta'
import { Botao } from '../../core/ui/Botao'
import { Campo } from '../../core/ui/Campo'
import { Cartao } from '../../core/ui/Cartao'
import { Carregando } from '../../core/ui/Carregando'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { somenteDigitos } from '../../modules/pessoas/tipos'
import { useIndicacaoPublica, useInfoIndicacao } from '../api'

/** Página pública do link de indicação: quem foi indicado deixa nome e telefone. Sem login. */
export function IndicacaoPublicaPage() {
  const { codigo = '' } = useParams()
  const info = useInfoIndicacao(codigo)
  const enviar = useIndicacaoPublica()
  const [nome, setNome] = useState(''); const [telefone, setTelefone] = useState(''); const [erro, setErro] = useState<string | null>(null)
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (nome.trim().length < 2) { setErro('Informe seu nome.'); return }
    if (somenteDigitos(telefone).length < 10) { setErro('Informe o telefone com DDD.'); return }
    setErro(null)
    enviar.mutate({ codigo, nome: nome.trim(), telefone: somenteDigitos(telefone) })
  }
  if (info.isPending) return <Carregando telaCheia />
  const cor = info.data?.cor ?? '#1e3a8a'
  return (
    <div className="flex min-h-screen items-center justify-center bg-surface p-4">
      <div className="w-full max-w-md">
        <div className="mb-6 rounded-lg p-6 text-center text-white" style={{ backgroundColor: cor }}>
          {info.data?.logo && <img src={info.data.logo} alt="" className="mx-auto mb-3 h-10 w-auto rounded bg-white/90 p-1" />}
          <p className="text-xs uppercase tracking-widest opacity-80">Indicação</p>
          <h1 className="mt-1 text-2xl font-semibold">{info.data?.negocio ?? 'Link inválido'}</h1>
          {info.data && <p className="mt-2 text-sm opacity-90">{info.data.indicador} indicou você{info.data.texto ? `. ${info.data.texto}` : '.'}</p>}
        </div>
        <Cartao>
          {!info.data ? <Alerta tipo="erro">Este link de indicação não é válido ou não está mais ativo.</Alerta>
            : enviar.isSuccess ? <Alerta tipo="sucesso" titulo="Recebemos seu contato">{enviar.data.repetida ? 'Você já tinha sido indicado. ' : ''}A equipe do {enviar.data.negocio} vai falar com você em breve.</Alerta>
            : (
              <form onSubmit={aoEnviar} className="space-y-4" noValidate>
                <p className="text-sm text-ink-muted">Deixe seu nome e telefone. A equipe entra em contato para explicar os planos.</p>
                {(erro || enviar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(enviar.error)}</Alerta>}
                <Campo rotulo="Seu nome" value={nome} onChange={(e) => setNome(e.target.value)} />
                <Campo rotulo="Seu telefone (com DDD)" inputMode="tel" value={telefone} onChange={(e) => setTelefone(e.target.value)} />
                <Botao type="submit" className="w-full" carregando={enviar.isPending}>Quero ser contatado</Botao>
              </form>
            )}
        </Cartao>
      </div>
    </div>
  )
}
