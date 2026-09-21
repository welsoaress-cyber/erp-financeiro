# ERP Financeiro Pessoal — regras do projeto

Leia `docs/01-arquitetura.md` antes de propor mudanças de estrutura. Cada etapa tem um doc em `docs/`.

## Regras inegociáveis (definidas pelo proprietário)
- **Custo zero.** Nada pago, nenhum serviço externo com cobrança, nada ativado sem autorização prévia. Informe antes: serviço, motivo, plano gratuito, limites, quando cobra.
- **Sem segredos no repositório.** Chaves só em `app/.env.local` (ignorado) e nas variáveis de build do Cloudflare. Nunca pedir credenciais pelo chat.
- **Banco isolado.** Projeto Supabase novo e exclusivo. Os projetos legados `holding-financeiro` e `navalha-app` não são tocados (nem pausados, nem alterados).
- **Só migrations versionadas alteram o banco.** Nenhuma outra ferramenta (DeepSeek, painel, scripts avulsos) cria objetos. Se uma migration falhar em produção, reportar o erro exato e parar; nunca contornar. Ver `docs/15-incidente-producao.md`.
- **Uma etapa por vez.** Entregar migration + testes SQL + app + e2e + doc, commitar, enviar, mergear na `main` (para o deploy do Cloudflare sair sozinho) e então pedir para o proprietário testar — não deixar em branch/PR parado esperando ação dele. Não antecipar funcionalidades. MVP simples.
- **Avisar antes** de implementar algo que prejudique a arquitetura (regra 9), com o motivo em uma ou duas frases, e então entregar sob premissas explícitas.
- **Crítica de dono proativa.** A cada entrega, apontar espontaneamente incoerências, riscos e melhorias adjacentes que o proprietário ainda não viu (como consumível × patrimônio, alerta de item nunca movimentado) — como SUGESTÃO numerada para ele aprovar; implementar só depois do sim. Isso não revoga o "não antecipar funcionalidades": sugerir é obrigatório, implementar sem pedido não.
- **Relatório junto com o dado.** Toda etapa que criar dados entrega, na MESMA entrega, o(s) relatório(s) correspondente(s) na Central de Relatórios (`docs/54-relatorios.md`): view versionada `security_invoker` + entrada em `app/src/modules/relatorios/catalogo.ts` + teste. Nunca SQL dinâmico nem query gravada em tabela.
- **Manual sempre atualizado.** Toda etapa nova que mudar telas ou fluxos inclui, na MESMA entrega, a atualização de `docs/manual/README.md` (texto e, quando a tela mudou, prints regerados com `cd app && npm run build && node scripts/prints-manual.mjs` — acrescentando os dados novos ao fixture do script).

## Stack e convenções
- `app/`: React 19 + TypeScript + Vite + Tailwind v4 + TanStack Query v5 + supabase-js + react-router 8. Deploy: Cloudflare Workers (assets estáticos) via push em `main`.
- `supabase/migrations/`: Postgres 17, uma migration por etapa, numeradas `20260902000NNN_*.sql`. Enums para tipos, `criado_em`/`atualizado_em`, `gen_random_uuid()`, RLS em toda tabela com `organizacao_id in (select public.minhas_organizacoes())`, sem grant de DELETE, nada para `anon`, funções com `set search_path = public`.
- **Motor financeiro:** `lancamentos` só é gravado pelas funções `criar/atualizar/efetivar/cancelar/excluir_lancamento` (flag de sessão `erp.motor`). Saldo e resultado são derivados (views), nunca gravados.
- Módulos em `app/src/modules/<nome>/` (`tipos.ts`, `api.ts`, `components/`, `pages/`, `index.ts`) registrados em `app/src/app/modulos.ts`. UI em `app/src/core/ui`. Textos em português.

## Como testar (obrigatório antes de commitar)
```
# Postgres local (16) em /var/tmp/erp-pg, porta 5433, socket /tmp, usuário postgres
PGHOST=/tmp PGPORT=5433 PGUSER=postgres supabase/tests/rodar_local.sh   # todas as suítes SQL + cenário de produção
cd app && npx tsc --noEmit -p tsconfig.app.json && npx oxlint src && npm run build
```
E2E: Playwright com API mock (`mock.mjs`, porta 54321) e `vite preview --port 4173`; um spec por módulo. Rodar os specs dos módulos tocados.

## Produção
- Verificação consolidada: `supabase/tests/verificar_tudo.sql` (esperado 77 de 77). Diagnóstico somente leitura: `supabase/scripts/diagnostico_contratos.sql`.
- O ambiente remoto não alcança `*.supabase.co` nem `workers.dev`: o proprietário aplica SQL pelo SQL Editor e reporta o resultado.

## Estilo de resposta
Custo mínimo, sem rodeios, assertivo. Um item por vez quando o proprietário estiver executando passos. Dar link raw do GitHub e o SQL para copiar/colar.
- Etapas 11B/12/13: `docs/18-portal-servnet.md`, `docs/19-dominio-portal.md`, `docs/20-recorrencia-fixa-parcelada.md`, `docs/21-financeiro.md`. Lançamentos vivem em `/financeiro/lancamentos`; mês compartilhado em `core/periodo/usePeriodo.ts`.
- Etapas 14/15: `docs/22-contratos-fornecedor.md`, `docs/23-resumo-financeiro-dashboard.md`.
- Etapa 16: `docs/24-pendencias-projecao-edicao.md`.
- Etapa 17: `docs/25-carteira-dupla-saldo.md`.
- Etapas 18-25: `docs/26-projecao-contratos.md`, `docs/27-cartao-credito.md` (meses futuros de contrato são projeção derivada, nunca lançamentos pré-gerados).
- Etapa 26: `docs/28-disparos.md` (disparos WhatsApp manuais a partir do PDF de receitas; login do servidor em pessoas).
- Etapa 28 (A/B): `docs/30-estoque.md` (Estoque Servnet: itens com custo médio ponderado, movimentações imutáveis, compra com pagamento misto gerando despesa; etapa B = instalações com porta FTTH e mão de obra, payback no contrato, relatórios e alertas no dashboard — concluída).
- Etapa 27 (A–F): `docs/29-ftth.md` (Rede FTTH: POP e CTOs no mapa Leaflet/OSM, fios com vértices, lacres por porta e por caixa, vínculo cliente↔porta via contrato ativo, histórico; endereço em pessoas alimenta o fio automático).
- Etapa 29 (A/B/C): `docs/31-ordens-servico.md` (Ordens de Serviço: chamados técnicos, bolsa do técnico, tempo desde o agendamento, comissão no Contas a Pagar, payback; 29A/B/C entregues: admin, técnico com login restrito e portal do cliente com avisos WhatsApp.
- Etapa 30: `docs/32-comodato.md` (Comodato: equipamentos com série na casa do cliente; OS de recolhimento automática no encerramento do contrato; troca/perda/descarte com histórico imutável).
- Etapa 31: `docs/33-pix-bloqueio.md` (Pix Mercado Pago no portal e no aviso WhatsApp com baixa automática via webhook; bloqueio assistido em Financeiro → Cobrança).
- Etapa 32: `docs/34-bi-gerencial.md` (BI gerencial em tempo real: churn, MRR, ticket, inadimplência, payback médio, técnicos, CSV — menu Gerencial).
- Etapa 33: `docs/35-ftth-ceo.md` (FTTH: CEO como tipo de ponto, encadeamento alimentado-por com impacto de rompimento, OLT como cadastro no POP).
- Etapa 34: `docs/36-olt-monitoramento.md` (agente local pinga a OLT → Edge olt-ping → aviso WhatsApp ao admin quando cai/volta; alerta na tela FTTH).
- Etapa 35: `docs/37-backup.md` (backup semanal via GitHub Actions → artifact privado 90 dias; secret SUPABASE_DB_URL).
- Etapa 36: `docs/38-aceite-contrato.md` (aceite digital do contrato no portal: termo por negócio, snapshot+hash, IP/user-agent via Edge portal-aceite).
- Etapa 37: `docs/39-excluir-pessoa-busca.md` (excluir pessoa sem histórico via função definer; busca em Contratos por nome/nº/CPF/login/telefone; menu reordenável e dashboard recolhível).
- Etapa 38: `docs/40-compra-print.md` (compra de estoque por print: OCR Tesseract.js no navegador pré-preenche a Nova compra).
- Etapa 39: `docs/41-natureza-categoria.md` (natureza operacional × investimento na categoria; resultado operacional no Resumo; centro de custo = negócio).
- Etapa 40: `docs/42-indique-ganhe-presente.md` (campanha Indique e Ganhe com presente do estoque: faixa por plano do indicado, escolha sem troca no portal, entrega ≤ 10 dias úteis, custo congelado para ROI).
- Etapa 41: `docs/44-patrimonio.md` (patrimônio como tabela própria de bens individuais — série, local, estado, baixa com histórico imutável; aba Patrimônio no Estoque com inventário e CSV; fora dos alertas de reposição).
- Etapa 42: `docs/45-fechamento-mes.md` (fechamento de mês: trava do realizado com baixa atrasada permitida; fechar/reabrir auditado em Financeiro → Lançamentos).
- Etapa 43: `docs/46-estorno.md` (estorno formal: contra-lançamento negativo datado de hoje, original intocado mesmo em mês fechado).
- Etapa 44: `docs/47-conciliacao.md` (conciliação bancária: conferir movimentos contra o extrato por conta/mês, aba Conciliação no Financeiro).
- Etapa 45: `docs/48-parcela-inicial.md` (parcelamento pode iniciar de parcela específica — numeração espelha o contrato: 2/24…24/24).
- Etapa 46: `docs/49-pix-reconciliacao.md` (reconciliação ativa do Pix: tela Cobrança re-consulta no MP os pendentes >1h via Edge pix-reconciliar).
- Etapa 47: `docs/50-confianca.md` (voto de confiança na Cobrança: segura o bloqueio até data; furou → volta destacado; cumprida/furada resolvidas em gerar_bloqueios).
- Etapa 48: `docs/51-regua-cobranca.md` (régua de cobrança configurável por negócio — listas regua_antes/regua_apos, padrão enxuto 2·dia·3; dias_antes/apos derivados).
- Etapa 49: `docs/52-vitrine-premios.md` (vitrine de prêmios do Indique e Ganhe: faixas e prêmios com foto configuráveis, escolha visual no portal com trava, aviso WhatsApp na conversão, vitrine pública /portal/premios/:slug).
- Etapa 51: `docs/49-pix-reconciliacao.md` §0077 (reconciliação Pix DENTRO do banco a cada minuto: pg_cron+pg_net+Vault `mp_access_token`, GET por txid + busca por external_reference, grava status em pix_cobrancas.resposta, baixa via pix_confirmar; migration *agendado* = pulada nos testes locais, validada com stubs).
- Etapa 54 (A + 0082): `docs/55-centros-custo.md` (centros de custo dentro do negócio — departamento/projeto/ponto de rede; coluna opcional em lançamentos e contratos de fornecedor, nulo = Geral; motor `definir_centro_custo_lancamento`; relatório Gastos por centro; sem tipos cliente/técnico/veículo; 0082: despesa vinculada ao contrato entra no payback e no relatório Custo por cliente — regra: comprou para um cliente, vincula ao contrato).
- Etapa 53 (A): `docs/54-relatorios.md` (Central de Relatórios: menu Relatórios, catálogo em código, uma view por relatório, tela genérica com filtros/ordenação/agrupamento/CSV/impressão/favoritos; 7 relatórios financeiros + custo por cliente (0082) + materiais em estoque/alocados em clientes (0083); resto de 53B/53C e 53D pendentes).
- Etapa 52: `docs/53-cortesia.md` (contrato cortesia: flag + check valor 0; 0080 = fatura nasce cancelada com motivo Cortesia — aparece, não conta; importação CSV com cortesia e escolha de plano existente).
- Etapa 50: menu próprio Indicações (módulo app/src/modules/indicacoes — métricas, converter/escolher/entregar e vitrine; Portal do cliente ficou só com aparência/promoções/acessos).
- Manual do administrador: `docs/manual/README.md` (tela a tela com prints; regerar com `app/scripts/prints-manual.mjs`).
- **Etapa 55A/B/C entregues** (0092/0093/0094): `docs/59-compras.md` — módulo Compras com fluxo formal ERP grande. 55A: Requisição + Aprovação + Pedido. 55B: Recebimento imutável + lançamento (à vista ou N parcelas mensais; cartão → fatura). 55C: destino patrimônio cria bem individual no recebimento; comodato tratado como estoque (aloca ao cliente depois); botão "Nova compra" do Estoque removido (redireciona para `/compras`). Aprovador = proprietário. Pendências: anexo da nota (Storage) e requisição automática por alerta de estoque baixo.
- **Etapa 56 entregue** (0095/0096/0099): `docs/60-api-integracoes.md` — API de consulta de cliente por CPF/CNPJ para integrações externas (Leveduca), já em produção. Token por negócio (hash sha256, valor puro só na criação), Edge Function `api-consulta-cliente` (Verify JWT desligado) chamando o RPC `api_consultar_cliente` (0096 — toda a lógica em uma função definer, service_role só precisa de EXECUTE, sem grant tabela por tabela), auditoria em `api_consultas` + relatório "Consultas à API". Configurações → Integrações via API. Premissas assumidas (confirmar com a Leveduca se der problema): chave `endereco` sem acento, `numero`/`cep` sempre nulos (endereço é texto único no cadastro), grafia `cpf_cnpj` corrigida do typo do PDF deles.
- **Etapa 57 entregue** (0097/0098): `docs/61-bloqueio-automatico.md` — bloqueio/desbloqueio automático, opt-in por negócio (`notificacoes_config.bloqueio_automatico`, desligado por padrão). Robô diário (pg_cron 00:00 Brasília) confirma sozinho quem bloquear/desbloquear — só pra quem já tem a rede (ReceitaNet/OLT) cortando/liberando por conta própria; o ERP não manda comando pra rede, só acompanha. Auditoria (`bloqueios.automatico`) + relatório "Bloqueios e desbloqueios". **Deploy pendente do proprietário**: migrations 0097 e 0098 pelo SQL Editor, nessa ordem (instruções no doc).
- **Etapa 58A entregue** (0100/0101): `docs/62-pontos-pontualidade.md` — motor de pontos por pontualidade: `pontos = dias_de_antecedência + 1` (sem teto, ajustado na 0101) sobre `lancamentos.data_vencimento_original` (fixo, nunca muda; reagendar só vale mês seguinte, auditado em `lancamentos_vencimento_historico`); só quitação total de contrato de receita principal (`contratos.elegivel_pontos`); opt-in por negócio (`notificacoes_config.pontos_ativo`); campanha com prazo fixo 01/10/2026 a 30/09/2027 (extensão é decisão futura do proprietário, não automática); contrato encerrado perde o saldo; estorno remove os pontos da fatura; pessoa excluída com saldo gera alerta em `pontos_perdidos_exclusao`. Relatório "Pontos de pontualidade".
- **Etapa 58B entregue** (0102): `docs/63-vitrine-pontos-resgate.md` — vitrine de prêmios + resgate. Catálogo `pontos_premios` (item do Estoque/Brindes + preço em R$; pontos = `ceil(valor/0,22)`). Prêmio físico: escolha no portal debita na hora (trava), entrega só pelo proprietário (Configurações → Programa de pontos) baixa o estoque e congela o custo real. Desconto em fatura: sem catálogo, cliente escolhe quantos pontos (R$0,25/ponto, mínimo 4 pontos), aplica na próxima fatura em aberto, 100% vira cortesia (cancelada). `vw_saldo_pontos` = ganhos − resgates. Portal → "Meus pontos" (saldo/vitrine/desconto/extrato). Relatório "Resgates de pontos (ROI)". Sem aviso de WhatsApp (decisão do proprietário).
- **Etapa 59 entregue** (0103): `docs/64-parcerias.md` — clube de benefícios no Portal (menu "Parcerias"). Duas origens: `leveduca` (lista ~500 parceiros, importada de CSV/XLSX pelo admin — cada importação substitui a lista inteira) e `servnet` (acordos próprios, cadastro manual). Configurações → Parcerias: importar planilha, cadastrar parceiro Servnet, ativar/desativar qualquer parceiro, e 3 espaços de foto por parceiro (arte pra baixar e compartilhar no Instagram/WhatsApp — não aparece no Portal). Portal do cliente: lista com busca + filtro de categoria, só leitura. Relatório "Parcerias cadastradas".
- **No radar (não iniciar sem o proprietário pedir):** SVA de câmera IP — campanha de câmera em comodato para quem migra ao plano maior + mensalidade de manutenção, em `docs/58-sva-camera-ip.md` (dois produtos com contas separadas; operável hoje com estoque + comodato + plano adicional; sem guardar imagem, por LGPD).
- **No radar (não iniciar sem o proprietário pedir):** SVA de ponto adicional/repetidor com mensalidade em vez de taxa de instalação — produto detalhado em `docs/57-sva-ponto-adicional.md` (já operável com plano + contrato adicional + comodato, sem etapa nova; falta só agrupar as duas cobranças numa fatura na visão do cliente).
- **No radar (não iniciar sem o proprietário pedir):** integração ReceitaNet (API URA/Callcenter — consulta de cliente/faturas por CPF/telefone via Edge Function com token em secret). Aguarda: proprietário ativar o módulo de API no plano do ReceitaNet e obter o token com o suporte.
