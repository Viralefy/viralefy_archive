---
date: 2026-06-14
session: round 15 (5 tracks paralelos)
---

# Round 15 — 5 tracks paralelos

Sequência dos rounds 13 e 14. Mesma arquitetura.

## FEITO

### Track J — i18n IT/RU/NL/KO em /pricing /vs /cities
- **Repo:** `viralefy_front`
- **Arquivos:** `src/middleware.ts`, `src/app/{pricing,vs/[competitor],cities/[city]}/page.tsx`
- **Mudança:** `PageLang` expandido de 6 pra 10 idiomas (`en|pt|es|fr|de|ja|it|ru|nl|ko`). Packs PRICING/VS/CITY_T com IT/RU/NL/KO completos. Traduções manuais idiomáticas (formal-comercial IT, cyrílico genitivo RU, direto NL, hangul formal `-니다/-십시오` KO). `neighborhoodsText` fallback ramificado.
- **Validado em prod:** 4 langs × 3 paths = 12 combos OK
  - IT /pricing → "Prezzi trasparenti in USDT"
  - RU /vs/socialplug → "сравнение бок о бок"
  - NL /cities/london → "Instagram-volgers kopen in London"
  - KO /pricing → "USDT 기반 투명한 가격"
- **Commit:** parte de `viralefy_front@274289f`

### Track L — CLAUDE.md em 10 repos
- **Mudança:** copiou template de `~/.claude/skills/padroes-engenharia/assets/CLAUDE.md` pra raiz de cada repo, customizado com cabeçalho específico do repo (linguagem, escopo, observações).
- **10 repos:** viralefy_core, viralefy_front, viralefy_auth, viralefy_payments, viralefy_sender, viralefy_backoffice, viralefy_ops, viralefy_archive, viralefy_api (legacy), viralefy_api_rust (legacy)
- **Commits individuais:** 1 por repo (10 commits no total). Hash mais recente por repo:
  - viralefy_core@bcc1132, viralefy_auth@b68b2e3, viralefy_payments@90c6904, viralefy_sender@8b71931, viralefy_backoffice@be71a8b, viralefy_ops@cf072a6, viralefy_api@32160d5, viralefy_archive@e9ae582, viralefy_api_rust@575d470
  - viralefy_front (CLAUDE.md junto com round 15) `274289f`

### Track M — hooks ativados (context-monitor + precompact-backup)
- **Arquivo:** `~/.claude/settings.json` (backup em `.bak.2026-06-14`)
- **Mudança:** adicionou `statusLine` apontando pra `context-monitor.mjs` (mostra ⚠ LIMITE no status bar quando passar de 250k tokens) e `hooks.PreCompact` apontando pra `precompact-backup.mjs` (backup automático em `<projeto>_archive/context` antes de cada /compact).
- **Threshold:** default 250k (override via env `CTX_THRESHOLD`).
- **Risco baixo:** scripts têm try/catch interno; em falha não bloqueiam UI/compact.

### Track N — 7 bugs mecânicos fechados (parte de 274289f)
| BUG | Descrição | Fix |
|---|---|---|
| 134 | `visualizacoes_tiktok` H1 mencionava Reels/Stories (formatos do Instagram) | `VIEWS_TIKTOK_OVERRIDES` em `categories.ts` sobrescreve só nessa categoria |
| 193 | `/jp` 109+ botões "Buy now" em inglês | `cta.buyNow: "今すぐ購入"` no override `ja` |
| 194 | `/kr` idem em coreano | `cta.buyNow: "지금 구매"` no override `ko` |
| 198/211 | `/fr` subtítulos "Ideal for testing"/"First push" em EN | `FOLLOWERS_TIERS`/`ENGAGEMENT_TIERS`/`VIEWS_TIERS` + `UNIT_FR/DE/IT/NL` em `plan-labels.ts` |
| 209 | `/jp` "View details →" em EN | `pickService`+`viewService` em ja/ko/ar/hi/id/vi/th/tr |
| 176/177 (residual) | `og:image:alt` e `og:site_name` ausentes em / /case-studies /help /status | Adicionado em 5 pages |

### Track K — .env hardening + Vary header (manual SSH)
- **Tarefa 1 (.env perm):** `chmod 0640 /etc/viralefy/.env` em prod (antes `600 root:viralefy`, agora `640 root:viralefy` — alinhado com installer). `systemctl restart viralefy-auth` → active. OK.
- **Tarefa 2 (Vary):** investigação mostrou que Caddyfile não strip Vary; o problema é o **layer interno do Next** sobrescrevendo `Vary` com o conjunto RSC após middleware e config. Tentativa de fix via `next.config.headers()` em `viralefy_front/next.config.ts` adicionando `Vary: Accept-Language, RSC, ..., Accept-Encoding` em /pricing /vs/* /cities/* /case-studies/* foi pushed (`viralefy_front@0dd24ce`) MAS o header em prod continua sem `Accept-Language` — o Next App Router injeta o Vary do RSC **após** as config rules. Marcado como débito conhecido (ver EM ABERTO).
- **Tarefa 3 (Track E persiste):** confirmado, `grep -c "preserve-env" /usr/local/sbin/viralefy-update` retorna 3.

## Deploy + smoke
- `viralefy-update` rodou completo (debt de migrations permanece resolvido)
- 7 services active
- `viralefy-smoke` 8/8 verde
- Smoke i18n: 12/12 combos OK (it/ru/nl/ko × /pricing /vs /cities)
- Vary header check: ainda só `rsc, next-router-*, Accept-Encoding` (Accept-Language NÃO presente)

## Commits da sessão
- `viralefy_front@274289f` — round 15 (i18n IT/RU/NL/KO + 7 bugs + CLAUDE.md)
- `viralefy_front@0dd24ce` — fix Vary tentativa (no-op na prática)
- 9 commits `docs: pin padroes-engenharia v5.3` em viralefy_{core,auth,payments,sender,backoffice,ops,archive,api,api_rust}

## EM ABERTO

### Vary: Accept-Language no Next App Router (débito não resolvido)
- next.config.headers() não vence o Vary que o layer App Router injeta.
- Possíveis caminhos: (a) custom server.ts que reescreve Vary no fluxo de resposta, (b) Cloudflare Workers/middleware no edge que appenda Accept-Language, (c) usar redirect-by-Accept-Language em vez de Vary (não-RESTful), (d) aceitar limitação e documentar.
- **Risco real:** se um CDN intermediário cachear `/pricing` sem honrar Accept-Language, usuário recebe lang do primeiro request. Hoje as rotas são `ƒ` (server-rendered dinâmico) → sem cache CDN. Risco minimal por enquanto.

### Bugs ainda em aberto
- BUG-94/95 likes TikTok preço alto — decisão de produto
- BUG-178 prefetch /tickets — pedir QA URL exata
- BUG-13 navbar duplicada — investigar timing/SSR
- BUG-29 highlight de campo no checkout error — refactor de state
- BUG-79/111 tema/moeda não persistem — Provider/storage refactor
- BUG-200 geo-redirect raiz — decisão de produto
- BUG-114/115 CN/JP script nativo — decisão de produto

### Débitos i18n remanescentes
- ar/zh/hi/tr/pl/sv/da/no/fi/cs/sk/hu/ro/bg/el/uk/th/vi/id/ms/tl/he/fa/ur/bn/sw/am — cobertura completa exigiria packs adicionais nas 3 páginas + entradas em `resolveLang`/`detectAcceptLanguage`. Template pronto.
- `ar`/`he`/`fa` exigem RTL no `<html dir>` — infra não tem hoje.

## Total da maratona após round 15
- Round 13: 4 tracks
- Round 14: 5 tracks
- Round 15: 5 tracks
- Bugs fechados acumulado: ~150 / 213 (70%)
