import type { ReactNode } from 'react'
import { Navigate } from 'react-router'
import { OrganizacaoContexto, type Organizacao } from './contexto'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../supabase/client'
import { useAuth } from '../auth/useAuth'
import { Carregando } from '../ui/Carregando'
import { Alerta } from '../ui/Alerta'
import { Botao } from '../ui/Botao'
import { mensagemDeErro } from '../erros/mensagemDeErro'

async function carregarOrganizacoes(): Promise<Organizacao[]> {
  const { data, error } = await supabase
    .from('organizacao_membros')
    .select('papel, organizacoes ( id, nome )')
    .order('criado_em', { ascending: true })
  if (error) throw error
  return (data ?? []).flatMap((m) => {
    const e = m.organizacoes as unknown as { id: string; nome: string } | null
    return e ? [{ id: e.id, nome: e.nome, papel: m.papel as Organizacao['papel'] }] : []
  })
}

/**
 * Carrega as organizações do usuário autenticado e fixa a organização atual.
 * Toda consulta de módulo futuro deve usar `useOrganizacao().organizacao.id`.
 */
export function OrganizacaoProvider({ children }: { children: ReactNode }) {
  const { usuario, sair } = useAuth()
  const consulta = useQuery({
    queryKey: ['organizacoes', usuario?.id],
    queryFn: carregarOrganizacoes,
    enabled: Boolean(usuario),
  })

  if (consulta.isPending) return <Carregando telaCheia texto="Carregando seus dados…" />

  if (consulta.isError) {
    return (
      <div className="mx-auto mt-16 max-w-lg space-y-4 p-6">
        <Alerta tipo="erro" titulo="Não foi possível carregar seus dados">{mensagemDeErro(consulta.error)}</Alerta>
        <div className="flex gap-2">
          <Botao onClick={() => consulta.refetch()}>Tentar novamente</Botao>
          <Botao variante="secundario" onClick={() => sair()}>Sair</Botao>
        </div>
      </div>
    )
  }

  const organizacoes = consulta.data
  if (organizacoes.length === 0 && (usuario?.user_metadata?.portal === 'true')) {
    return <Navigate to="/portal" replace />
  }
  if (organizacoes.length === 0) {
    return (
      <div className="mx-auto mt-16 max-w-lg space-y-4 p-6">
        <Alerta tipo="erro" titulo="Nenhuma organização vinculada ao seu usuário">
          A organização deveria ter sido criada automaticamente no cadastro. Entre em contato com o administrador.
        </Alerta>
        <Botao variante="secundario" onClick={() => sair()}>Sair</Botao>
      </div>
    )
  }

  return <OrganizacaoContexto.Provider value={{ organizacao: organizacoes[0], organizacoes }}>{children}</OrganizacaoContexto.Provider>
}
