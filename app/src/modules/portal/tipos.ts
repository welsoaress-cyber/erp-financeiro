export interface PortalConfig { id: string; organizacao_id: string; negocio_id: string; ativo: boolean; logo_url: string | null; cor_primaria: string; texto_promocional: string | null; chave_pix: string | null; instrucoes_pagamento: string | null; beneficio_indicacao: number }
export type DadosPortalConfig = Omit<PortalConfig, 'id' | 'organizacao_id' | 'negocio_id'>
export interface PromocaoAdmin { id: string; organizacao_id: string; negocio_id: string; plano_id: string | null; titulo: string; descricao: string; regras: string | null; como_aderir: string | null; data_inicio: string; data_fim: string | null; ativa: boolean }
export type DadosPromocao = Omit<PromocaoAdmin, 'id' | 'organizacao_id'>
export interface IndicacaoAdmin { id: string; negocio_id: string; indicador_pessoa_id: string; nome_indicado: string; telefone_indicado: string; indicado_pessoa_id: string | null; status: 'pendente' | 'convertida' | 'cancelada'; beneficio_valor: number; observacao: string | null; criado_em: string }
export interface AcessoPortal { id: string; pessoa_id: string; pessoa: string; codigo_indicacao: string; criado_em: string; indicacoes: number }
