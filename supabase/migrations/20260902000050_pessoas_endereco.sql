-- =============================================================================
-- 0050 · Endereço no cadastro de pessoas
-- =============================================================================
-- Usado pelo módulo FTTH: ao desenhar o fio até o cliente, o mapa busca o
-- endereço do cadastro automaticamente. Texto livre ("rua, número, bairro,
-- cidade"), sem validação de CEP nesta versão.
-- =============================================================================

alter table public.pessoas add column endereco text
  check (endereco is null or char_length(endereco) <= 200);
comment on column public.pessoas.endereco is 'Endereço do cliente (rua, número, bairro, cidade) — usado no mapa FTTH.';
