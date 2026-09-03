# Etapa 6D — Importação de clientes por CSV (SERVNET)

Status: **implementada e testada localmente (03/09/2026); aguardando aplicação da migration 0011 em produção, teste com o arquivo real e validação do proprietário.**

## 1. Objetivo
Trazer clientes, planos e contratos do sistema anterior da SERVNET para o ERP **sem acesso ao banco legado**: o proprietário exporta um CSV, sobe na tela, confere a prévia e confirma. Nada é gravado antes da confirmação.

## 2. Como funciona
```
CSV (navegador) → leitura e mapeamento de colunas → linhas em JSON
   → RPC importar_clientes(negócio, linhas, simular, faturar_desde)
        ├─ plano: reaproveita pelo nome ou cria no negócio (mensal)
        ├─ pessoa: reaproveita pelo CPF/CNPJ (nunca duplica) ou cria
        ├─ vínculo "cliente" (trigger do contrato)
        └─ contrato: cria; com Data do Cancelamento → encerra na mesma hora
   → relatório linha a linha (importada / rejeitada / já existe + motivo)
```
- **Simulação = execução real desfeita no final.** A RPC roda o mesmo caminho e faz `rollback` do bloco inteiro quando `p_simular = true`. O relatório da simulação é, por construção, idêntico ao da importação.
- **Cada linha é atômica.** Erro em uma linha desfaz só ela (subtransação) e a marca como rejeitada; as demais seguem.
- **Idempotente.** Reimportar o mesmo arquivo não cria nada: pessoas são achadas pelo documento, planos pelo nome, contratos por (pessoa, negócio, plano, data de início) → "já existe".
- Passa pelos **mesmos triggers e RLS** de sempre (`security invoker`): não há caminho privilegiado.

## 3. Regras de validação (banco = fonte da verdade; a tela só antecipa)
| Campo | Regra |
|---|---|
| Nome | obrigatório, 2–120 caracteres |
| CPF/CNPJ | obrigatório, dígitos verificadores válidos (`documento_valido`), único na organização; 14 dígitos ⇒ pessoa jurídica |
| Telefone | obrigatório, 10–13 dígitos (DDD + número) |
| E-mail | opcional; se presente, formato válido |
| Plano | obrigatório; `Velocidade_0100_MB` → **Plano 100 Mbps** (`nome_plano_importado`); outros nomes só são limpos |
| Valor | opcional; aceita `R$ 99,90`; vazio ⇒ valor de tabela do plano; ao criar o plano, vira seu valor de tabela |
| Dia de vencimento | obrigatório, 1–31 |
| Data de início de cobrança | obrigatória; `AAAA-MM-DD` ou `DD/MM/AAAA` (nunca interpretada como MM/DD) |
| Data do cancelamento | opcional; ≥ início ⇒ contrato **encerrado** com `data_fim`, faturamento automático desligado |
| Linha repetida | mesmo documento + plano + início no próprio arquivo ⇒ rejeitada |

Pessoa já cadastrada com o mesmo CPF/CNPJ é **reaproveitada sem sobrescrever** nome/telefone/e-mail (o cadastro do ERP prevalece). Pessoa ou plano inativos ⇒ linha rejeitada.

## 4. Decisão de arquitetura: "faturar a partir de"
A especificação pedia `faturar_desde = data_inicio`. Para um contrato ativo desde 2022 isso faria o faturamento automático gerar **todas as competências desde 2022** como previstos, cobranças que já foram feitas no sistema anterior. Por isso a tela tem o campo **"Faturar contratos ativos a partir de"**, com padrão no 1º dia do mês atual:
- preenchido ⇒ `faturar_desde = max(data informada, data_inicio)`;
- vazio ⇒ `faturar_desde = data_inicio` (comportamento literal da especificação).

`data_inicio` continua sendo a "Data de Início de Cobrança" do CSV, preservando o histórico do contrato.

## 5. Tela (Configurações → Importar CSV)
1. **Arquivo e destino**: negócio (SERVNET pré-selecionado pelo slug/nome), "faturar a partir de", arquivo CSV. Separador (`;` `,` tab), aspas, BOM e codificação (UTF-8 / Windows-1252) detectados automaticamente.
2. **Colunas**: mapeamento sugerido pelo nome do cabeçalho (nome, cpf/cnpj, telefone, e-mail, plano/velocidade, valor, vencimento, início/cobrança, cancelamento), ajustável campo a campo. Obrigatórias sem coluna bloqueiam.
3. **Pré-visualização**: tabela com validação local ("Verificar" + motivo). **Simular importação** chama a RPC em modo simulação e mostra, por linha, OK / Rejeitada / Já existe, "pessoa existente", "plano novo", "encerrado". Só depois libera **Importar N linha(s)**.
4. **Relatório**: totais (linhas, importadas, rejeitadas, já existentes, pessoas novas/reaproveitadas, planos criados, contratos ativos/encerrados) e a lista de rejeitadas com linha e motivo.

Limite: 2000 linhas por arquivo. Arquivo de exemplo: `docs/exemplos/importacao_exemplo.csv`.

## 6. Banco (migration `20260902000011_importacao.sql`)
- `nome_plano_importado(text)`, `data_importada(text)` — helpers imutáveis.
- `importar_clientes(p_negocio_id uuid, p_linhas jsonb, p_simular boolean = true, p_faturar_desde date = null) → jsonb`.
- Sem tabela nova. Execute apenas para `authenticated`; nada para `anon`/`public`.

## 7. Testes
- `supabase/tests/importacao_test.sql`: helpers (mapeamento, datas DD/MM), simulação sem gravar, importação real (pessoa reaproveitada, CNPJ ⇒ jurídica, plano com valor do CSV, contrato encerrado com `data_fim`, `faturar_desde`), reimportação idempotente, segundo contrato da mesma pessoa, negócio inativo/inexistente, linhas inválidas, papel `anon` negado.
- `supabase/tests/verificar_importacao.sql`: 4 verificações somente leitura para rodar em produção após a migration.
- e2e (Playwright + mock): orientação sem negócio, leitura do CSV, mapeamento automático, validação local, campo com `;` entre aspas, coluna obrigatória desmapeada, simulação com motivos, nada gravado na simulação, importação real, relatório, contratos/pessoas resultantes, reimportação sem duplicar.

## 8. Fora do escopo (não feito de propósito)
- Importar histórico de faturas/pagamentos do sistema anterior (o saldo e a DRE do ERP começam na data de corte).
- Atualizar dados de pessoas já existentes a partir do CSV.
- Agendar ou repetir importações; integração por API com o sistema antigo.

## 9. Como aplicar em produção
1. SQL Editor → rodar `supabase/migrations/20260902000011_importacao.sql`.
2. Rodar `supabase/tests/verificar_importacao.sql` → esperado **4 de 4**.
3. Deploy do app (push em `main` → Cloudflare).
4. Configurações → Importar CSV → arquivo real → **Simular** → conferir → **Importar**.
