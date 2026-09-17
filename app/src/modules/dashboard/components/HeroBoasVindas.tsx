const MENTA = '#4ee6b8'

/**
 * Capa do Dashboard: mesma linguagem visual do login (fundo escuro, faixas de
 * luz) com um motivo de "rede" — nós ligados por linhas — no lugar do mapa,
 * porque aqui a rede é a do provedor, não uma rota de trânsito. Decorativo:
 * não lê dado nenhum, só recebe o nome da organização para a saudação.
 */
export function HeroBoasVindas({ nomeOrganizacao }: { nomeOrganizacao: string }) {
  const hora = new Date().getHours()
  const saudacao = hora < 12 ? 'Bom dia' : hora < 18 ? 'Boa tarde' : 'Boa noite'

  return (
    <div className="relative mb-6 overflow-hidden rounded-3xl px-6 py-8 sm:px-10 sm:py-10"
      style={{ background: 'radial-gradient(120% 140% at 15% 0%, #123a30 0%, #0a1613 55%, #050907 100%)' }}>
      <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden opacity-80">
        <svg viewBox="0 0 800 260" className="absolute -right-10 top-0 h-full w-[70%] min-w-[420px]" preserveAspectRatio="xMidYMid slice">
          <g fill="none" stroke={MENTA} strokeLinecap="round">
            <path d="M20 220 L140 220 L200 150 L340 150 L400 70 L620 70 L680 30" strokeOpacity="0.12" strokeWidth="10" />
            <path d="M20 220 L140 220 L200 150 L340 150 L400 70 L620 70 L680 30" strokeOpacity="0.55" strokeWidth="2.5" />
            <path d="M60 250 L180 190 L260 190 L320 110 L500 110 L560 170 L720 170" strokeOpacity="0.08" strokeWidth="8" />
            <path d="M60 250 L180 190 L260 190 L320 110 L500 110 L560 170 L720 170" strokeOpacity="0.35" strokeWidth="1.5" />
          </g>
          <g fill={MENTA}>
            <circle cx="20" cy="220" r="5" opacity="0.9" />
            <circle cx="400" cy="70" r="4" opacity="0.7" />
            <circle cx="680" cy="30" r="6" opacity="0.95" />
            <circle cx="320" cy="110" r="4" opacity="0.6" />
          </g>
          <circle cx="680" cy="30" r="12" fill="none" stroke={MENTA} strokeOpacity="0.5" strokeWidth="1.5" />
        </svg>
        <span className="absolute left-1/3 top-0 h-32 w-[60%] -translate-x-1/2 rounded-full blur-3xl" style={{ background: `radial-gradient(circle, ${MENTA}22, transparent 70%)` }} />
      </div>

      <div className="relative">
        <div className="mb-3 flex items-center gap-2">
          <span className="flex size-7 items-center justify-center rounded-full border-2" style={{ borderColor: MENTA }}>
            <span className="size-2 rounded-full" style={{ backgroundColor: MENTA }} />
          </span>
          <span className="text-xs font-semibold tracking-[0.3em] text-white/70">ERP FINANCEIRO</span>
        </div>
        <h1 className="text-2xl font-bold text-white sm:text-3xl">
          {saudacao}, <span style={{ color: MENTA }}>{nomeOrganizacao}</span>
        </h1>
        <p className="mt-1 max-w-md text-sm text-white/50">A visão geral do seu negócio está logo abaixo.</p>
      </div>
    </div>
  )
}
