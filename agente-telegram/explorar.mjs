// PoC — explorador do painel via Telegram (userbot). Roda NA SUA MÁQUINA.
// Objetivo desta 1ª fase: logar como você, entrar no painel (/entrar + usuário +
// senha) e deixar você navegar vendo as respostas e os BOTÕES do bot, para a
// gente mapear o fluxo do "Ativar" antes de automatizar. Não ativa nada sozinho.
//
// Uso:
//   npm install
//   node explorar.mjs
// Na 1ª vez ele pede telefone + código (e senha 2FA, se tiver) e imprime uma
// TELEGRAM_SESSION — cole no .env para as próximas execuções não pedirem de novo.
//
// Comandos no prompt (depois de logado no painel):
//   <texto>            envia o texto ao bot (ex.: um login de cliente)
//   /b                 lista os botões da última mensagem do bot
//   /click N           clica no botão de número N (ver /b)
//   /ver               reimprime a última resposta do bot
//   /sair              encerra
import 'dotenv/config'
import input from 'input'
import { TelegramClient } from 'telegram'
import { StringSession } from 'telegram/sessions/index.js'

const apiId = Number(process.env.TELEGRAM_API_ID)
const apiHash = process.env.TELEGRAM_API_HASH
const botHandle = process.env.PAINEL_BOT           // ex.: @algum_bot
const usuario = process.env.PAINEL_USUARIO
const senha = process.env.PAINEL_SENHA
if (!apiId || !apiHash || !botHandle) { console.error('Faltam TELEGRAM_API_ID / TELEGRAM_API_HASH / PAINEL_BOT no .env'); process.exit(1) }

const session = new StringSession(process.env.TELEGRAM_SESSION ?? '')
const client = new TelegramClient(session, apiId, apiHash, { connectionRetries: 5 })

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
let bot, ultima

async function ultimaDoBot() {
  const msgs = await client.getMessages(bot, { limit: 1 })
  return msgs[0]
}
function imprimir(m) {
  if (!m) return console.log('(sem resposta)')
  console.log('\n🤖 ' + (m.message || '(sem texto)'))
  const linhas = m.replyMarkup?.rows ?? []
  const botoes = linhas.flatMap((r) => r.buttons.map((b) => b.text))
  if (botoes.length) console.log('   botões: ' + botoes.map((t, i) => `[${i}] ${t}`).join('  '))
  console.log('')
}
async function enviar(texto) {
  await client.sendMessage(bot, { message: texto })
  await sleep(2500)
  ultima = await ultimaDoBot(); imprimir(ultima)
}

;(async () => {
  await client.start({
    phoneNumber: async () => await input.text('Telefone (com +55): '),
    password: async () => await input.text('Senha 2FA (se tiver, senão Enter): '),
    phoneCode: async () => await input.text('Código que o Telegram enviou: '),
    onError: (e) => console.error(e),
  })
  const s = client.session.save()
  if (!process.env.TELEGRAM_SESSION) console.log('\n>>> Salve no .env:  TELEGRAM_SESSION=' + s + '\n')

  bot = await client.getEntity(botHandle)
  console.log('Conectado ao painel:', botHandle)

  // entra no painel
  await enviar('/entrar')
  if (usuario) await enviar(usuario)
  if (senha) await enviar(senha)

  console.log('--- Agora navegue. Comandos: <texto> | /b | /click N | /ver | /sair ---')
  for (;;) {
    const cmd = (await input.text('> ')).trim()
    if (cmd === '/sair') break
    else if (cmd === '/ver') { ultima = await ultimaDoBot(); imprimir(ultima) }
    else if (cmd === '/b') imprimir(ultima)
    else if (cmd.startsWith('/click ')) {
      const n = Number(cmd.split(' ')[1])
      try { await ultima.click({ i: n }); await sleep(2500); ultima = await ultimaDoBot(); imprimir(ultima) }
      catch (e) { console.log('falha ao clicar:', String(e)) }
    }
    else if (cmd) await enviar(cmd)
  }
  await client.disconnect()
  process.exit(0)
})()
