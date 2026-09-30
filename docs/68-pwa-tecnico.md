# 68 · App mobile do técnico (PWA) — Etapa 63

PWA "raso" pra área do técnico, sem migration (etapa só de front-end). Escopo aprovado pelo proprietário — **sem foto/câmera** (já existia antes desta etapa, ver correção abaixo), **sem push**, **sem offline de escrita** (nunca — risco de ação duplicada/perdida no motor de OS).

## Correção de fato (relevante pro histórico)

Na avaliação anterior a esta etapa eu disse que Storage nunca tinha sido ativado no projeto — **errado**: `os-fotos` já está em uso desde a etapa 29 (upload em `useEnviarFoto`, leitura via URL assinada em `useFotosOs`, `<input capture="environment">` já no encerramento de chamado). Só não achei porque busquei em `src/modules/os` e esqueci `src/tecnico`. Não muda o escopo desta etapa (câmera já tinha sido excluída por outro motivo), só o registro.

## O que entrega

- **`manifest.webmanifest`** (`public/`), `scope`/`start_url` = `/painel/tecnico` — o prompt de instalação do navegador só aparece dentro da área do técnico, não no ERP admin inteiro. Ícones gerados (aro+ponto na cor da marca, `#4ee6b8` sobre `#0b1512`) em 192/512, normal e maskable.
- **`sw.js`** (`public/`) — Service Worker "raso": só cache de leitura.
  - Navegação (HTML): **network-first** — nunca serve tela velha se tiver internet; cai pro cache só sem sinal.
  - Assets com hash (`/painel/assets/…`), ícones e o próprio manifest: **cache-first** (são imutáveis por URL).
  - Chamadas à API (Supabase, outro domínio): **sempre rede, nunca cache** — decisão deliberada, dado de negócio não fica em cache de Service Worker.
  - Registrado só em produção (`import.meta.env.PROD`), pra não atrapalhar o `npm run dev`.
- **Agenda semanal do técnico** (`/tecnico/agenda`, nova aba na barra inferior): grade simples (sem lib de calendário) dos chamados já agendados, dia a dia da semana corrente, com navegação ‹ › entre semanas. Reaproveita `useMeusChamados()` e o mesmo modal de detalhe (`DetalheTecnico`, exportado de `TecnicoChamadosPage.tsx`) que "Meus chamados" já usa — nenhuma lógica de chamado duplicada.

## Fora do escopo, por decisão explícita

- Fila de sincronização offline (escrever sem internet) — as ações do técnico (iniciar/pausar/encerrar) passam por funções do motor com efeito colateral real (consome bolsa, gera comissão); enfileirar isso offline arrisca duplicar ou conflitar com o que mudou no servidor nesse meio-tempo.
- Push notifications — infra nova (VAPID, tabela de inscrições, Edge Function) e suporte frágil no iPhone; proprietário usa Android e não é prioridade agora.
- Câmera/fotos — já existia, fora do escopo desta etapa por decisão do proprietário (Storage não seria autorizado *se* fosse preciso, mas não era).

## Teste manual

Sem suíte SQL (não há migration). Validado no navegador (mobile 420×860, mock local): manifest resolve e é válido, Service Worker registra com `scope: /painel/`, a Agenda mostra os chamados do técnico logado agrupados por dia da semana corrente e abre o detalhe ao tocar. `npx tsc`/`oxlint`/`npm run build` limpos.
