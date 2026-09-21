# Etapa 59: Parcerias (clube de benefícios) no Portal do cliente

## Motivo

O dono tem acesso ao clube de benefícios da Leveduca (~500 parceiros com desconto — Casas Bahia, Dell, Cruzeiro do Sul etc.) e quer que o cliente veja isso no Portal, além de poder destacar acordos locais próprios da Servnet.

## O que foi feito

- **Tabela `parcerias`** por negócio, com `origem` = `leveduca` (lista grande, vem de importação) ou `servnet` (acordos próprios, cadastro manual).
- **Importação da lista da Leveduca**: Configurações → Parcerias → sobe a planilha (CSV ou XLSX) que a Leveduca manda. Cada importação **substitui inteiramente** a lista anterior daquele negócio — não acumula duplicado. O cadastro manual (origem `servnet`) nunca é tocado pela importação.
- **Cadastro manual** (Servnet): nome, benefício, tipo (Online/Presencial), categoria e cobertura — mesmo padrão de formulário da vitrine de pontos.
- **Ativo/Inativo**: qualquer parceiro (Leveduca ou Servnet) pode ser ativado/desativado com um clique — sai da vitrine do Portal na hora, sem apagar o cadastro.
- **3 espaços de foto por parceiro** (Leveduca ou Servnet): o proprietário guarda a arte promocional ali (comprime no navegador, como as fotos da vitrine de pontos) e depois entra, baixa e compartilha no Instagram/WhatsApp quando quiser. **Não aparece no Portal do cliente** — é uso interno, de divulgação.
- **Portal do cliente** — menu "Parcerias": lista com busca (nome/benefício) e filtro por categoria. Só leitura, sem cadastro do lado do cliente.
- **Relatório "Parcerias cadastradas"** na Central de Relatórios: todas as parcerias (Leveduca + Servnet), com origem, categoria e situação.

## Regras importantes

- Criar uma parceria com `origem = 'leveduca'` direto (fora da função de importação) é bloqueado — só a importação em massa cria esse tipo. Depois de criada, qualquer parceria (de qualquer origem) pode ser editada normalmente (ativo/inativo, fotos).
- A busca/filtro de categoria no Portal roda no navegador (a lista inteira, ~500 itens, é leve o bastante pra isso — sem paginação no servidor).
- Fotos são `data:image/...` comprimidas no navegador, até ~400 KB cada, guardadas na própria linha da parceria (mesmo padrão do prêmio da vitrine de pontos).

## Deploy (proprietário)

1. Aplicar a migration `20260902000103_parcerias.sql` pelo SQL Editor.
2. No app, Configurações → Parcerias → escolher o negócio → subir a planilha da Leveduca (botão "Importar lista da Leveduca").
3. Cadastrar parceiros próprios da Servnet, se quiser, e guardar as fotos que for usar pra divulgar.
