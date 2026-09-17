# Etapa 56: API de consulta de cliente (integrações externas)

## Motivo

A Leveduca (clube de benefícios revendido junto do plano — 300 licenças, negociado com a Servnet) precisa consultar, a partir do CPF, se a pessoa é cliente ativo e qual o plano. Hoje isso passaria pelo ReceitaNet; quando migrar para este ERP, o endpoint já precisa existir no mesmo formato que a Leveduca documentou para outros provedores (anexo `CONSULTA_API_Integrações`).

## O que foi feito

- **Token por negócio**, gerado pelo app (Configurações → Integrações via API). O valor em texto puro só existe no momento da criação — o banco grava só o hash (sha256). Perdeu, revoga e gera outro.
- **Edge Function `api-consulta-cliente`** (Verify JWT desligado — quem chama não tem sessão nossa): recebe `POST` com header `Token` e corpo `{"cpf_cnpj": "..."}`, valida o hash, busca a pessoa por CPF **dentro do negócio do token**, e devolve nome, e-mail, endereço, status do cliente e do plano.
- **Auditoria**: toda consulta (achou ou não) fica registrada em `api_consultas`, com o CPF mascarado no relatório (`Relatórios → Consultas à API`).
- RLS: `api_tokens`/`api_consultas` só listam para membro da organização; nenhum grant de insert/update para `authenticated` — só as funções `criar_api_token`/`revogar_api_token` (definer, checam `exigir_membro`) e o `service_role` da Edge Function escrevem.

## Contrato do endpoint

```
POST {SUPABASE_URL}/functions/v1/api-consulta-cliente
Content-Type: application/json
Token: <token gerado no app>

{"cpf_cnpj": "12345678901"}
```

Resposta (200):
```json
{
  "cliente": {
    "cpf_cnpj": "12345678901",
    "nome_completo": "Fulano de Tal",
    "status_cliente": "Ativo",
    "email": "fulano@email.com",
    "endereco": "Rua das Flores, 120 — Centro",
    "numero": null,
    "cep": null,
    "plano": "Fibra 300 Mega",
    "plano_id": "<uuid>",
    "status_plano": "Ativo"
  }
}
```
404 se o CPF não é cliente daquele negócio; 401 se o token for inválido/revogado.

## Premissas assumidas (avisar se algo estiver errado)

1. **Chave "endereço"**: o PDF da Leveduca mostra a chave com acento (`"endereço"`); usei `endereco` sem acento na resposta pra evitar problema de encoding do lado deles — confirme com a Leveduca se o parser aceita, senão eu troco.
2. **`numero`/`cep` sempre nulos**: o cadastro de Pessoas guarda o endereço como texto único (rua, número, bairro juntos) — não temos os campos separados. Se a Leveduca **exigir** esses campos separados, é preciso separar o campo de endereço no cadastro (mudança maior, avisar antes de fazer).
3. **`status_cliente`**: "Ativo" se a pessoa está ativa e tem contrato de receita ativo nesse negócio; "Suspenso" se o contrato está suspenso; "Inativo" nos demais casos (sem contrato, contrato encerrado, ou pessoa inativa).
4. **Typo do exemplo**: o PDF usa `"cpf_cpnj"` (letras trocadas) na resposta de exemplo — usei a grafia correta `cpf_cnpj` nos dois lugares; se o backend deles espera literalmente o typo, é só avisar.

## Deploy (proprietário)

1. Aplicar a migration `20260902000095_api_consulta_cliente.sql` pelo SQL Editor.
2. Painel Supabase → Edge Functions → Deploy `api-consulta-cliente` com **Verify JWT desligado**. Nenhum secret novo (só `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`, injetados pela plataforma).
3. No app, Configurações → Integrações via API → Novo token → negócio Servnet → nome "Leveduca". Copiar o token (só aparece uma vez) e o endpoint mostrado na tela, e repassar pra Bianca (Leveduca).
