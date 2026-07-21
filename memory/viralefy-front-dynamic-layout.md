---
name: viralefy-front-dynamic-layout
description: O layout raiz do viralefy_front é dinâmico (headers/cookies) e isso anula o ISR, joga a metadata pro body e força no-store
metadata:
  type: project
---

`viralefy_front/src/app/layout.tsx` faz `await headers()` e `await cookies()` (i18n +
tema). Isso torna **toda rota dinâmica**, com três consequências medidas em 2026-07-21:

1. `Cache-Control: private, no-cache, no-store` em toda página → reprova `bf-cache`
   no Lighthouse e mata o back/forward cache.
2. `<title>` e `<meta name="description">` são **streamados pro `<body>`**, não pro
   `<head>` (medido: `</head>` na posição 4763, a meta na 260360). Lighthouse pontua
   `meta-description` 0 e a categoria SEO trava em 0.92; crawler sem JS não lê.
3. **O `export const revalidate = 1800` da home não tem efeito** — a página é SSR a
   cada request, que é justamente o que o comentário do round 23 diz ter resolvido.

**Why:** parece chatice do Lighthouse, mas (3) é performance real em produção e (2) é
SEO real. Fácil diagnosticar errado e desligar o gate.

**How to apply:** corrigir = tirar `headers()`/`cookies()` do layout raiz (detecção no
middleware + segmento de rota por idioma). Raio grande (26 idiomas) — merece ADR antes.
Use [[viralefy-index-generator]] pra levantar os call sites e o raio de impacto.
