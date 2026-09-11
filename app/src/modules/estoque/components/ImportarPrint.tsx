import { useCallback, useEffect, useRef, useState } from 'react'
import { Alerta } from '../../../core/ui/Alerta'
import { Botao } from '../../../core/ui/Botao'

/** O que conseguimos ler de um print de pedido (Shopee, Mercado Livre, e-mail…). */
export interface DadosPrint {
  descricao: string | null
  total: number | null
  quantidade: number | null
}

const reValor = /R?\$\s*([\d.]+,\d{2})/g
const paraNumero = (s: string) => Number(s.replace(/\./g, '').replace(',', '.'))

/** Heurística sobre o texto do OCR: total do pedido, produto e quantidade. */
export function extrairDadosPedido(texto: string): DadosPrint {
  const linhas = texto.split('\n').map((l) => l.trim()).filter(Boolean)
  let total: number | null = null
  let quantidade: number | null = null
  let descricao: string | null = null

  for (const l of linhas) {
    if (total === null && /total\s*(do\s*pedido)?/i.test(l) && !/subtotal|frete|desconto|cupom/i.test(l)) {
      const m = [...l.matchAll(reValor)]
      if (m.length > 0) total = paraNumero(m[m.length - 1][1])
    }
  }
  if (total === null) {
    // maior valor positivo do print (ignora linhas de desconto "-R$")
    let maior = 0
    for (const l of linhas) {
      if (l.includes('-R$') || /desconto|cupom/i.test(l)) continue
      for (const m of l.matchAll(reValor)) maior = Math.max(maior, paraNumero(m[1]))
    }
    if (maior > 0) total = maior
  }

  const mq = texto.match(/(?:^|\s)x\s?(\d{1,3})(?:\s|$)/im)
  if (mq) quantidade = Number(mq[1])

  // produto: a linha "de texto" mais longa, fora rótulos, valores e endereço
  const ignorar = /pedido|pagamento|frete|desconto|cupom|subtotal|total|entrega|endereço|chat|loja|moedas|coins|cart[aã]o|parcelamento|r\$|\d{5}-?\d{3}|\(\+?\d/i
  let melhor = ''
  for (const l of linhas) {
    if (ignorar.test(l)) continue
    if (l.length > melhor.length && l.length >= 12) melhor = l
  }
  if (melhor) descricao = melhor.replace(/^(sob encomenda|frete gr[áa]tis|indisponível)\s*/i, '').replace(/\s+/g, ' ').slice(0, 120)

  return { descricao, total, quantidade }
}

/** Painel de importação: cole (Ctrl+V), arraste ou escolha o print; o OCR roda no navegador. */
export function ImportarPrint({ aoExtrair, aoFechar }: { aoExtrair: (d: DadosPrint) => void; aoFechar: () => void }) {
  const [lendo, setLendo] = useState(false)
  const [progresso, setProgresso] = useState(0)
  const [erro, setErro] = useState<string | null>(null)
  const arquivoRef = useRef<HTMLInputElement>(null)

  const processar = useCallback(async (imagem: File | Blob) => {
    setErro(null)
    setLendo(true)
    setProgresso(0)
    try {
      const { createWorker } = await import('tesseract.js')
      const worker = await createWorker('por', 1, {
        logger: (m) => { if (m.status === 'recognizing text') setProgresso(Math.round(m.progress * 100)) },
      })
      const { data } = await worker.recognize(imagem)
      await worker.terminate()
      const dados = extrairDadosPedido(data.text)
      if (!dados.total && !dados.descricao) {
        setErro('Não consegui ler o print. Tente um print de tela (não foto) com o total visível — ou preencha manualmente.')
        return
      }
      aoExtrair(dados)
    } catch (e) {
      setErro(`Falha ao ler a imagem: ${e instanceof Error ? e.message : String(e)}`)
    } finally {
      setLendo(false)
    }
  }, [aoExtrair])

  useEffect(() => {
    function aoColar(e: ClipboardEvent) {
      const item = [...(e.clipboardData?.items ?? [])].find((i) => i.type.startsWith('image/'))
      const f = item?.getAsFile()
      if (f) { e.preventDefault(); void processar(f) }
    }
    window.addEventListener('paste', aoColar)
    return () => window.removeEventListener('paste', aoColar)
  }, [processar])

  return (
    <div className="space-y-3 rounded-md border border-dashed border-line bg-surface/60 p-4">
      {erro && <Alerta tipo="erro">{erro}</Alerta>}
      <div
        onDragOver={(e) => e.preventDefault()}
        onDrop={(e) => { e.preventDefault(); const f = e.dataTransfer.files[0]; if (f?.type.startsWith('image/')) void processar(f) }}
        className="flex flex-col items-center gap-2 py-4 text-center text-sm text-ink-muted"
      >
        {lendo ? (
          <p>Lendo o print… {progresso}%</p>
        ) : (
          <>
            <p><strong>Cole o print aqui (Ctrl+V)</strong>, arraste a imagem ou</p>
            <Botao variante="secundario" onClick={() => arquivoRef.current?.click()}>Escolher imagem</Botao>
            <p className="text-xs">Funciona melhor com print de tela do pedido (Shopee, Mercado Livre, e-mail). Os campos vêm preenchidos para você conferir.</p>
          </>
        )}
        <input ref={arquivoRef} type="file" accept="image/*" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void processar(f); e.target.value = '' }} />
      </div>
      <div className="flex justify-end">
        <button type="button" className="text-xs font-medium text-ink-muted hover:underline" onClick={aoFechar}>Fechar importação</button>
      </div>
    </div>
  )
}
