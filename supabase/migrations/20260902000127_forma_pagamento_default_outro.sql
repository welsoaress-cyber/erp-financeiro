-- =============================================================================
-- 0127 · forma_pagamento nasce "outro" (não "pix")
-- =============================================================================
-- Pedido do proprietário: o default 'pix' da 0126 deixava todo contrato
-- existente marcado como pix silenciosamente — sem forçar ele a decidir, não
-- dava pra saber quem ainda falta classificar. "Outro" é um estado neutro
-- ("ainda não decidi") que ele vai trocando, contrato a contrato, por pix ou
-- boleto conforme for revisando.
-- =============================================================================

alter table public.contratos alter column forma_pagamento set default 'outro';

-- Ninguém escolheu "pix" de propósito até agora — era só o default da 0126.
update public.contratos set forma_pagamento = 'outro' where forma_pagamento = 'pix';
