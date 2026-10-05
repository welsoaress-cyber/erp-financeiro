# 72 · Importar nota fiscal (XML)

Migration `20260902000128_notas_fiscais_importadas.sql`. Módulo `app/src/modules/notas_fiscais`. Botão em Compras ("Importar XML de nota") e atalho no Dashboard.

## Pedido do proprietário
Subir o XML da nota (procNFe) recebida do fornecedor e deixar o sistema ajudar a lembrar o fluxo: já é fornecedor cadastrado? Já tem requisição/pedido em aberto? É material (vai pro estoque) ou serviço? É recorrente (SVA, tipo o curso da Leveduca)?

## Arquitetura: só uma peça de SQL nova
O assistente **não inventa um caminho novo pro dinheiro** — orquestra as funções do motor que já existem (mesma regra do módulo Compras: "a compra não grava nada sozinha"):
- Fornecedor novo → `pessoas` (insert direto, RLS já permite)
- Item de estoque novo → `estoque_itens` (via `useSalvarEstoqueItem`, já existente)
- Compra avulsa/com requisição → `criar_requisicao_compra` + `aprovar_requisicao_compra` + `registrar_recebimento_compra` (0092/0093/0094, inalteradas)
- Nota recorrente, 1ª vez → `contratos` (insert direto, igual Novo contrato)
- Nota recorrente, 2ª vez em diante → `efetivar_lancamento` (dá baixa na fatura que o contrato já gerou sozinho)

A única coisa que não existia: **impedir importar a mesma nota duas vezes**, em qualquer um desses caminhos. Daí a tabela nova `notas_fiscais_importadas` (chave de acesso única) + a função `registrar_nota_fiscal_importada`, chamada **por último**, só depois que a compra/baixa real já foi criada — assim uma importação que falha no meio do caminho nunca trava a chave.

## Leitura do XML: 100% no navegador
`parseNFeXml` usa `DOMParser` nativo do navegador — sem biblioteca, sem upload pra nenhum servidor. **O arquivo XML não fica guardado em lugar nenhum** (decisão do proprietário, evita ativar Supabase Storage/custo novo); só os dados extraídos (chave, número, itens, fornecedor, valor) viram lançamento/estoque/contrato.

## Fluxo do assistente
1. Escolhe o arquivo → parse → bloqueia se a nota não estiver **autorizada** (`cStat ≠ 100`) ou se a **chave já foi importada** antes.
2. Escolhe o **negócio** (o XML nunca diz isso — sempre manual).
3. **Fornecedor**: casa por CNPJ com `pessoas.documento` (só dígitos); sem match, mostra os dados da nota e só cadastra com confirmação.
4. Marca se é **recorrente**:
   - Não: cada item vira **Material (estoque)**, **Despesa** ou **Serviço** — pro estoque, tenta casar sozinho com um item já cadastrado (heurística simples por palavras em comum no nome); sem achar, pergunta: cadastrar item novo ou virar despesa. Depois, lista **pedidos abertos deste fornecedor** e **requisições pendentes do negócio** pra marcar (ticar) — nenhum marcado = compra avulsa (cria requisição + aprova na hora, igual uma compra sem vínculo prévio). Requisição pendente marcada é aprovada na hora (pedido novo vira recebimento).
   - Sim: se já existe contrato de fornecedor ativo pra essa pessoa+negócio, só pede a conta e dá baixa na fatura em aberto do contrato (avisa, sem travar, se o valor da fatura for diferente do valor da nota); senão, cria o contrato de fornecedor (despesa mensal, valor da nota).
5. Pagamento (conta, parcelas, já pago) quando aplicável.
6. Importar → registra a chave por último.

## Limites do MVP (de propósito)
- Destino do item cobre **estoque, despesa e serviço** — patrimônio e comodato continuam só pelo fluxo manual de Compras (são raros numa nota de fornecedor comum; se precisar, dá pra estender).
- Casamento de item de estoque é heurística simples (palavras em comum) — sempre revisável/trocável na tela antes de confirmar.
- Casamento de requisição é manual (o proprietário marca) — o XML não tem como saber sozinho qual requisição é aquela.
- Um CNPJ só — não lida com nota com múltiplos destinatários/transportadora.

## Teste
`supabase/tests/notas_fiscais_test.sql`: destino exige compra_id/contrato_id coerente; chave mal formada falha; nota grava certo (compra e contrato); mesma chave duas vezes bloqueia; negócio de fora da organização falha.

## Validação manual do parser
`parseNFeXml` testado contra o XML real da nota Nubbi/Leveduca (300 × R$0,90 = R$270) num navegador headless — chave, número, data, fornecedor e item saíram corretos.
