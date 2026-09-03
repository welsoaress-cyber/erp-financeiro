import { useState, type FormEvent } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'
import { Selecao } from '../../../core/ui/Selecao'
import { mensagemDeErro } from '../../../core/erros/mensagemDeErro'
import type { Pessoa } from '../../pessoas/tipos'
import { formatarTelefone } from '../../pessoas/tipos'
import { useEnviarTeste } from '../api'
import { TIPOS_TESTE } from '../tipos'

export function EnviarTeste({ negocioId, pessoas, aoConcluir }: { negocioId: string; pessoas: Pessoa[]; aoConcluir: () => void }) {
  const enviar = useEnviarTeste()
  const [pessoaId, setPessoaId] = useState('')
  const [tipo, setTipo] = useState<string>('vencimento')
  const [erro, setErro] = useState<string | null>(null)
  const comFone = pessoas.filter((p) => p.ativo && p.telefone)
  function aoEnviar(e: FormEvent) {
    e.preventDefault()
    if (!pessoaId) { setErro('Selecione o cliente.'); return }
    setErro(null)
    enviar.mutate({ negocioId, pessoaId, tipo }, { onSuccess: aoConcluir })
  }
  return (
    <form onSubmit={aoEnviar} className="space-y-4" noValidate>
      {(erro || enviar.error) && <Alerta tipo="erro">{erro ?? mensagemDeErro(enviar.error)}</Alerta>}
      <Selecao rotulo="Cliente" opcoes={[{ valor: '', rotulo: 'Selecione…' }, ...comFone.map((p) => ({ valor: p.id, rotulo: `${p.nome} · ${formatarTelefone(p.telefone)}` }))]} value={pessoaId} onChange={(e) => setPessoaId(e.target.value)} ajuda={comFone.length === 0 ? 'Nenhuma pessoa ativa com telefone cadastrado.' : 'Só pessoas com telefone.'} />
      <Selecao rotulo="Modelo de mensagem" opcoes={TIPOS_TESTE} value={tipo} onChange={(e) => setTipo(e.target.value)} />
      <p className="text-xs text-ink-muted">Modo simulado: a mensagem é registrada no histórico com o prefixo [TESTE] e não é enviada.</p>
      <div className="flex justify-end gap-2"><Botao type="submit" carregando={enviar.isPending} disabled={comFone.length === 0}>Registrar teste</Botao></div>
    </form>
  )
}
