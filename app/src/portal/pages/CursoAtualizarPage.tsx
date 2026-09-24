import { useState, type FormEvent } from 'react'
import { Alerta } from '../../core/ui/Alerta'
import { Botao } from '../../core/ui/Botao'
import { Campo } from '../../core/ui/Campo'
import { Cartao } from '../../core/ui/Cartao'
import { mensagemDeErro } from '../../core/erros/mensagemDeErro'
import { somenteDigitos } from '../../modules/pessoas/tipos'
import { useCursoAtualizarCadastro, useCursoBuscarPessoa, type CursoPessoa } from '../api'

/** Página pública (sem login): cliente que vai fazer o curso na Leveduca confirma CPF/e-mail/
 *  nascimento pelo telefone — o ERP atualiza o cadastro e já vincula o contrato cortesia do curso. */
export function CursoAtualizarPage() {
  const [telefone, setTelefone] = useState('')
  const [pessoa, setPessoa] = useState<CursoPessoa | null>(null)
  const buscar = useCursoBuscarPessoa()
  const atualizar = useCursoAtualizarCadastro()
  const [cpf, setCpf] = useState(''); const [email, setEmail] = useState(''); const [nascimento, setNascimento] = useState('')

  function aoPesquisar(e: FormEvent) {
    e.preventDefault()
    atualizar.reset()
    buscar.mutate(telefone, {
      onSuccess: (d) => {
        setPessoa(d)
        setCpf(d.cpf ?? ''); setEmail(d.email ?? ''); setNascimento(d.data_nascimento ?? '')
      },
    })
  }
  function aoAtualizar(e: FormEvent) {
    e.preventDefault()
    if (!pessoa?.pessoa_id) return
    atualizar.mutate({ pessoaId: pessoa.pessoa_id, cpf: somenteDigitos(cpf), email: email.trim(), dataNascimento: nascimento })
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface p-4">
      <div className="w-full max-w-md">
        <div className="mb-6 rounded-lg bg-brand-700 p-6 text-center text-white">
          <p className="text-xs uppercase tracking-widest opacity-80">Curso Leveduca</p>
          <h1 className="mt-1 text-2xl font-semibold">Confirme seu cadastro</h1>
          <p className="mt-2 text-sm opacity-90">Pra liberar seu acesso ao curso, confirme CPF, e-mail e data de nascimento.</p>
        </div>
        <Cartao className="space-y-4">
          <form onSubmit={aoPesquisar} className="space-y-4" noValidate>
            <Campo rotulo="Seu telefone (com DDD)" inputMode="tel" value={telefone} onChange={(e) => { setTelefone(e.target.value); setPessoa(null); atualizar.reset() }} placeholder="(11) 95449-0001" />
            {buscar.error != null && <Alerta tipo="erro">{mensagemDeErro(buscar.error)}</Alerta>}
            {!pessoa && <Botao type="submit" className="w-full" carregando={buscar.isPending} disabled={somenteDigitos(telefone).length < 10}>Pesquisar</Botao>}
          </form>

          {pessoa && !pessoa.encontrado && (
            <Alerta tipo="erro">Não encontramos cadastro com esse telefone. Fale com a Servnet pra confirmar seu número.</Alerta>
          )}

          {pessoa?.encontrado && !atualizar.isSuccess && (
            <form onSubmit={aoAtualizar} className="space-y-4" noValidate>
              <p className="text-sm text-ink-muted">Olá, <b>{pessoa.nome}</b>! Confirme (ou corrija) seus dados abaixo.</p>
              {atualizar.error != null && <Alerta tipo="erro">{mensagemDeErro(atualizar.error)}</Alerta>}
              <Campo rotulo="CPF" inputMode="numeric" value={cpf} onChange={(e) => setCpf(e.target.value)} placeholder="000.000.000-00" />
              <Campo rotulo="E-mail" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
              <Campo rotulo="Data de nascimento" type="date" value={nascimento} onChange={(e) => setNascimento(e.target.value)} />
              <Botao type="submit" className="w-full" carregando={atualizar.isPending}>Atualizar</Botao>
            </form>
          )}

          {atualizar.isSuccess && (
            <Alerta tipo="sucesso" titulo="Cadastro atualizado!">Você já está inscrito no curso. Qualquer dúvida, fale com a Servnet.</Alerta>
          )}
        </Cartao>
      </div>
    </div>
  )
}
