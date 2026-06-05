# Viralefy — Context (snapshot 2026-06-05)

Dossiê operacional pra reconstruir o estado da plataforma sem perda em sessões futuras. Substitui o snapshot de 2026-06-01. Combina com `COMPLIANCE.md` (auditoria viva vs `diretrizes.md`) e `diretrizes.md` (normativo).

## TL;DR

Marketplace global de seguidores / curtidas / comentários / compartilhamentos / views pra Instagram e TikTok, mais 4 verticais (Account Recovery, Facebook BMs, perfis envelhecidos, email packs).

- **Storefront**: https://www.viralefy.com (canônico em www; apex e http redirecionam 301 em 1 hop após fix do Caddy).
- **Admin**: https://admin.viralefy.com — login `admin@viralefy.local` / `SimTest!Admin2026`.
- **API**: https://api.viralefy.com — Go, chi, OTel, métricas Prometheus.
- **Observability**: https://obs.viralefy.com — Grafana 12.
- Stack em **HML** (Hetzner CX31, Debian 13) até ~2026-06-14. Após esse prazo decisão PRD.

15 categorias × 130 países × ~97 planos × 47 idiomas. Sitemap ~18.7k URLs canônicas + IndexNow re-submitting completo.

---

## 1. Acesso e infraestrutura

- **IP**: `62.238.41.231` · **DNS**: Cloudflare A apex+www.
- **SSH**: chave OpenSSH em `/media/sonne/Archives/projects/viralefy/credentials`.
- **Acesso**: `ssh -i /tmp/key root@62.238.41.231` (extrair com `awk '/BEGIN OPENSSH/,/END OPENSSH/'`).
- **Caddy 2.11** TLS auto · zstd+gzip · HSTS preload · X-Robots-Tag.
- **Postgres 17** em `127.0.0.1:5432` · senha em `/etc/viralefy/.env` (`POSTGRES_PASSWORD`).
- **systemd hardened** units: `viralefy-{api,front,backoffice}` + `caddy` + obs stack.

### Caddy site blocks (`viralefy_ops/config/Caddyfile`)
- `http://viralefy.com` → `https://www.viralefy.com{uri}` (1 hop 301, fix da redirect chain 2026-06-05).
- `viralefy.com` (https) → mesma coisa.
- `www.viralefy.com` → `127.0.0.1:3000` (Next storefront) + X-Robots-Tag explícito.
- `admin.viralefy.com` → `127.0.0.1:3001` (Next backoffice) + CSP frame-ancestors none.
- `api.viralefy.com` → `127.0.0.1:8080` (Go API).
- `obs.viralefy.com` → `127.0.0.1:3030` (Grafana).

### CLIs locais no servidor
- `viralefy-update [--yes]` — destrutivo: `rm -rf /viralefy/*` + reclona main de cada repo + rebuild + restart. `/etc/viralefy/.env` e Postgres ficam intocados.
- `viralefy-status` — `systemctl status` agregado.
- `viralefy-logs` — `journalctl -u viralefy-*`.

---

## 2. Repos GitHub (org `Viralefy`)

| Repo | Branch | Diretório local | Stack |
|---|---|---|---|
| `viralefy_api` | main | `/media/sonne/Archives/projects/viralefy/viralefy_api` | Go 1.23, chi, pgx, slog, OTel |
| `viralefy_front` | main | `viralefy_front` | Next.js 15 App Router, React 19 |
| `viralefy_backoffice` | main | `viralefy_backoffice` | Next.js 15 |
| `viralefy_ops` | main | `viralefy_ops` | bash installers, Caddyfile, systemd |
| `viralefy_archive` | main | `viralefy_archive` | docs, brand, tasks |

---

## 3. Arquitetura

### `viralefy_api` (DDD 4-layer)
- **domain/** — entities + repositories interfaces puras (sem deps)
- **application/** — services orquestrando domain + infra ports
- **infrastructure/** — Postgres impls, email (Resend/SMTP), payment providers (Woovi/Heleket), Turnstile, OG scraper, observability
- **interface/http/** — handlers chi + middleware (AdminAuth, UserAuth, RequirePermission, RateLimit, Idempotency)

### `viralefy_front`
- Server components dominantes. `force-dynamic` na maioria das LPs (SEO precisa de fetch fresh do catálogo).
- App Router. Metadata API pra SEO. Open Graph + JSON-LD em `@graph`.
- i18n manual em `src/i18n/{languages,countries,categories,legal}.ts` (47 langs, 130 países, 15 categorias).
- Componentes principais: `BuyPlanCta`, `CheckoutModal`, `Header`, `Footer`, `TrustSignals`, `RecoveryForm`, `LiveCounter`, `CategoryGroupedGrid`, `QuantitySlider`.

### `viralefy_backoffice`
- Mesma stack Next 15. EN-default desde 2026-06-04 (admin tinha PT misturado, traduzido inteiro).
- Páginas: `/dashboard`, `/orders`, `/orders/[id]`, `/users`, `/users/[id]`, `/invoices`, `/invoices/[id]`, `/plans`, `/plans/[id]/edit`, `/currencies`, `/gateways`, `/tickets`, `/tickets/[id]`, `/reviews`.
- RBAC enforcement via `can()` helper local + permission check no API.

---

## 4. Domínio / Schema do Postgres

### Migrations atuais (`internal/infrastructure/persistence/postgres/migrations/`)
1. `001_init.up.sql` — users, plans, orders, payment_gateways, admins
2. `002_features.up.sql` — categories
3. `003_plan_prices.up.sql` — plan_prices (currency code → price string)
4. `004_rbac.up.sql` — roles, role_permissions
5. `005_payment.up.sql` — currencies, invoices (recargas de saldo)
6. `006_helpdesk.up.sql` — tickets, ticket_messages
7. `007_profiles_credits.up.sql` — profiles (IG/TT), credit_accounts, credit_transactions
8. `008_split_engagement.up.sql` — split de "engajamento" em curtidas/comentarios/shares por plataforma
9. `009_usdt_default.up.sql` — flip USDT como display canônico
10. `010_marketplace_recovery.up.sql` — categorias recovery + bms_facebook + perfis_redes + emails_validados; orders.custom_data + orders.ticket_id
11. `011_usd_base_rates.up.sql` — currency rates flip BRL-base → USD-base
12. `012_idempotency_audit.up.sql` — idempotency_keys + audit_log
13. `013_tracking.up.sql` — orders.tracking JSONB + users.tracking_data + indexes em fbclid/gclid/client_id/utm_campaign
14. `014_baseline_metrics.up.sql` — orders.baseline_metrics + delivery_metrics + captured_at + source
15. `015_reviews.up.sql` — reviews table (UNIQUE order_id, CHECK rating 1-5, visible bool) + orders.review_email_sent_at

### Roles RBAC seeded
| Role | Permissões |
|---|---|
| superadmin | plans:read+write, gateways:read+write, currencies:read+write, orders:read, tickets:read+write, reviews:read+moderate, admins:manage |
| manager | plans, gateways, currencies, orders, tickets, reviews:read+moderate |
| support | plans:read, gateways:read, currencies:read, orders:read, tickets:read+write, reviews:read |
| viewer | tudo `:read`, reviews:read |

### Categorias (15)
seguidores_instagram, seguidores_tiktok, curtidas_instagram, curtidas_tiktok, comentarios_instagram, comentarios_tiktok, compartilhamentos_instagram (inclui saves), compartilhamentos_tiktok, visualizacoes_instagram, visualizacoes_tiktok, servicos, recuperacao_perfil, bms_facebook, perfis_redes, emails_validados.

### Moedas seeded (`internal/infrastructure/persistence/postgres/seed.go`)
USDT (`$`, rate 1, canônica), USD (`$`, rate 1), EUR (`€`, rate 0.92), BRL (`R$`, rate 5.41 — mercado BR-only), BTC (`₿`, rate 0.0000103).

---

## 5. SEO completo (estado pós-Ahrefs audit 2026-06-05)

### hreflang
- `src/lib/hreflang.ts` — 4 helpers (homeAlternates, countryRootAlternates, categoryAlternates, slugAlternates). Cada tipo de página é seu próprio grupo. x-default sempre aponta pra variante en-US **do mesmo grupo**, nunca `/`.
- 20 invariantes em `tests/unit/hreflang.test.mjs`.

### Robots
- `src/app/robots.ts` — User-agent: *, Allow /, Disallow /account /tickets /login /register /api/. Sitemap declarado. `Host:` directive removida (legacy Yandex, RFC 9309 não suporta).
- `<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1">` em todas LPs públicas via `src/lib/seo-meta.ts`.
- `X-Robots-Tag` HTTP idem via Caddy.

### Dates
- `src/lib/seo-meta.ts`: `SITE_LAUNCH_DATE = "2026-01-01T00:00:00Z"`.
- `<meta name="article:published_time">` + `article:modified_time` em todas LPs.
- `WebPage.datePublished` + `dateModified` no JSON-LD.

### JSON-LD
- `src/lib/jsonld.ts` — `buildHomeJsonLd` + `buildCountryJsonLd` retornam `{ @context, @graph: [...] }` (1 script tag por página).
- Home: Organization + WebSite + Service com AggregateOffer.offers contendo TODOS os planos (Offer com image, shippingDetails, hasMerchantReturnPolicy, priceValidUntil).
- Country/Category/Slug: Organization + WebSite + WebPage + BreadcrumbList + Service + AggregateOffer + Offer por plano. WebPage carrega datePublished/dateModified.
- Marketplace index: CollectionPage + BreadcrumbList + ItemList.
- Marketplace sub-pages: BreadcrumbList + Service + AggregateOffer + Offer por plano + FAQPage.
- Slug page: Product com image + aggregateRating (quando há reviews) + Offer (com enhancements).
- `buildAggregateRating(agg)` retorna null quando review_count=0 (anti-fake policy do Google).
- `sameAs` da Organization vazio (GitHub removido por feedback do owner em 2026-06-05).

### Merchant Listings enhancements (em todo Offer)
`buildOfferEnhancements(countryCode)` retorna `shippingDetails` (OfferShippingDetails $0 USD, 0-day handling, 0-1 day transit) + `hasMerchantReturnPolicy` (FiniteReturnWindow 30 dias, FreeReturn, ReturnByMail, applicableCountry).

### Sitemap
- `src/app/sitemap.ts` — sitemapindex + 47 buckets per-lang (`/sitemap/{lang}.xml`) + bucket `legal`.
- `export const revalidate = 3600` (1h) + `fetchPlans` com `next.revalidate: 3600` (era no-store, causava slow page Ahrefs).
- Sitemap completo: ~18.7k URLs canônicas.

### IndexNow
- `/api/indexnow` POST com `INDEXNOW_SECRET` header → submete todas URLs canônicas em chunks de 10k pra `https://www.bing.com/indexnow`.
- Re-submit completo feito em todos os deploys recentes.

### Legal pages
- `src/i18n/legal.ts` — `legalMetaDescription(lang, slug)` extrai primeiro parágrafo do body + sufixo de marca, truncado em 158 chars (era "Privacy Policy — Viralefy" = 25 chars, Ahrefs flagava em massa).
- Cada variante `?lang=X` self-canonicaliza (antes TODAS canonicalizavam pra ?lang=en).

### Footer links
- `src/components/Footer.tsx` adicionou seção Marketplace (Overview + 3 sub-paths) — antes `/marketplace` era orphan e sub-paths tinham 1 incoming link.

---

## 6. Currency (USD-canonical multi-currency)

- **Canonical**: USD-cents internamente em TUDO (plan.price_cents, invoice.amount_cents, credit_accounts.balance_cents, credit_transactions.amount_cents).
- **Display**: usuário escolhe currency em `Providers.tsx` (default USDT, persistido em localStorage).
- **Conversion**: backend `CurrencyService.QuoteForPlan(prices, usdCents, displayCode)` → manual price se houver, senão deriva de USD × rate.
- **Settlement**: USD exibe → USDT cobra; BRL exibe → BRL cobra (PIX local); USDT/BTC self-settle.
- **PRESETS top-up**: `[10, 25, 50, 100, 250, 500]` em USD canônico (era `[50,100,200,500,1000,2000]` em "reais"; bug crítico).
- **Backoffice credit adjust**: form é "Δ em USD ($)" — antes "Δ em R$" e admin entrava 50 achando R$50 mas saía $50 (≈ R$270). Bug silencioso resolvido em 01e90e0.

---

## 7. i18n / Idioma

- **Default global**: EN (Open Graph locale `en_US`).
- **pt-BR**: SÓ quando country=BR ou usuário escolheu PT no seletor.
- **Backoffice**: EN-default desde 2026-06-04 (toda PT removida; `tests/unit/no-pt-regression.test.mjs` guarda).
- **Front**: 47 langs em `PACKS` (src/i18n/languages.ts) + 130 países com `htmlLang` BCP47.
- **Geo detection**: `/api/geo` lê `CF-IPCountry` ou Accept-Language → fallback USDT.
- **Email templates**: EN-only por enquanto (Build*Email helpers em `viralefy_api/internal/application/email_template*.go`). Localização por `user.locale` é follow-up.

---

## 8. Crons rodando

| Cron | Intervalo | Delay | Batch | Função |
|---|---|---|---|---|
| `DeliveryCaptureCron` | 15m | 24h | 25 | Snapshot 2ª fonte de verdade (perfil/post público) pra pedidos paid há > 24h |
| `ReviewRequestCron` | 1h | 168h (7d) | 50 | Email "How was your order?" pós-paid + link `/orders/{id}/review` |
| `IdempotencyCleanupCron` | 1h | — | 500 | DELETE FROM idempotency_keys WHERE expires_at < NOW() (TTL 24h) |

Padrão comum: `atomic.Bool` guard contra double-start, `Start(ctx)`/`Stop()`, tick imediato no boot, fail-warn-continue em erros individuais.

---

## 9. Reviews (feature completa, deploy 2026-06-04)

- Submissão em `/orders/[id]/review` (5-star + headline + body). Idempotency-Key + rate-limit no backend.
- Trigger: `ReviewRequestCron` 7d pós-paid → email com link.
- Hidratação author: `"First L."` via SPLIT_PART no Postgres.
- Visualização: stars badge sob H1 + seção "Customer reviews" no plan slug page.
- aggregateRating no JSON-LD do Product (null quando count=0).
- Admin moderation: `/reviews` no backoffice com filtro All/Hidden + Hide/Restore. Permissões `reviews:read` + `reviews:moderate` no RBAC.
- Endpoints: `POST /v1/me/reviews`, `GET /v1/me/reviews/by-order/{id}`, `GET /v1/plans/{id}/reviews`, `GET /v1/categories/{code}/reviews`, `GET /v1/admin/reviews`, `PATCH /v1/admin/reviews/{id}`.

---

## 10. Anti-fraude / Tracking captado (mas não enforced)

- `orders.tracking` JSONB: utm_source/medium/campaign/term/content, fbclid, gclid, ttclid, msclkid, referrer, landing_url, client_id (gerado client-side em `src/lib/tracking.ts`, persistido em localStorage), viewport, user_agent.
- `users.tracking_data` igual no momento do register.
- Backend `enrichTracking` adiciona IP, UA, X-Forwarded-For.
- **AINDA NÃO**: velocity rules, fingerprint, email reputation. Ver `RECOMMENDATIONS.md` Tier 1.

---

## 11. Pagamento

- **Providers ativos**: Woovi (BRL/PIX), Heleket (USDT/BTC). Manual PIX como fallback.
- **Webhooks**: `/v1/webhooks/woovi`, `/v1/webhooks/heleket` — assinatura validada (HMAC) antes de processar.
- **PaymentReceiver.onOrderPaid**: dispara em paralelo `maybeOpenTicket` (high-touch categories: recovery, bms_facebook, perfis_redes) + `sendConfirmationEmail` + `notifyAdmin` (Slack-compatible webhook em `ADMIN_WEBHOOK_URL`).
- **Idempotency-Key** obrigatório em /checkout e /recovery-request (24h TTL, SHA256 body hash).
- **Mínimo recarga**: $5 USD (500 cents).

---

## 12. Tests

| Surface | Suite | Tests |
|---|---|---|
| viralefy_api | `go test ./...` | 92 |
| viralefy_front | `npm test` | 358 |
| viralefy_backoffice | `npm test` | 4 (regression guard PT) |
| **Total** | | **454** |

### Suites no viralefy_api
- `application/`: currency, email templates EN, invoice input, review service, review email, idempotency cron, delivery cron
- `interface/http/`: helpers (clientIP, bearerToken, writeError envelope), ratelimit, middleware (RequirePermission, principal ctx)

### Suites no viralefy_front
- format (priceFor, formatBalance, formatPresetUsd)
- jsonld (deep, merchant listing, currency priority, aggregate rating, home)
- hreflang (20 invariantes: x-default rules, reciprocity, group isolation)
- robots (Host directive removed guard)
- categories, geo-currency, languages, plan-slugs, sitemap-xml, site-urls-integrity, theme
- no-brl-leak (anti-regressão BRL como default)

---

## 13. Comandos úteis

```bash
# Deploy
ssh -i /tmp/key root@62.238.41.231 "viralefy-update --yes"

# IndexNow (re-submit all 18.7k URLs)
curl -X POST https://www.viralefy.com/api/indexnow \
  -H "x-indexnow-secret: $INDEXNOW_SECRET" \
  -H "Content-Type: application/json" -d '{}'

# Tests
cd viralefy_api && go test ./...
cd viralefy_front && npm test
cd viralefy_backoffice && npm test

# Logs
ssh -i /tmp/key root@62.238.41.231 "journalctl -u viralefy-api -n 200 --no-pager | grep cron"

# DB
ssh -i /tmp/key root@62.238.41.231 "sudo -u postgres psql -d viralefy -c '\\d reviews'"
```

---

## 14. Decisões importantes / Quirks

1. **HML/POC**: rotação de segredos NÃO necessária até ~2026-06-14. Memory file `no-secret-rotation-nag.md` cobre.
2. **USDT é canonical**, não BRL nem USD. Símbolo `$` porque 1:1 com USD globalmente. BRL é subsidiária — só BR market.
3. **Admin em EN**, mesmo a equipe sendo BR. Locale-aware via `toLocaleString()` sem args (browser default).
4. **Email pt-BR removido** — todos templates em EN. Localização por `user.locale` é follow-up.
5. **GitHub removido do sameAs** em 2026-06-05 (owner pediu — sameAs é pra perfis sociais oficiais, não repos).
6. **`@graph` wrapper** em todo JSON-LD pra evitar visualizer "duplicação" via @id expansion.
7. **Force-dynamic** em maioria das LPs porque catálogo precisa ser fresh (mas sitemap cacheado 1h pra Ahrefs slow page fix).
8. **next/og crash em Arabic countries** (lookupType 5 substFormat 3) — workaround: OG image usa Intl.DisplayNames("en") pra nome do país; localized text só em og:title e document.title.

---

## 15. Recent commits (top de cada repo)

### viralefy_api
- `326496d` feat(reviews): admin moderation + user-visible reviews + idempotency cleanup cron
- `7fa5476` feat(reviews): post-delivery review collection — aggregateRating in JSON-LD
- `b9e15a1` feat(cron,http): delivery capture cron (24h post-paid) + 42 new Go tests
- `8658109` test: Go tests for currency/invoice/email — USD-cents + EN invariants
- `1d8cc5c` fix(emails,invoice): English-default templates, USD-cents canonical comments

### viralefy_front
- `2a38fe9` feat(seo): explicit robots meta + article:published/modified dates
- `0c47bb5` fix(seo): JSON-LD as single @graph + drop GitHub sameAs
- `6973be4` feat(seo): full Product/Offer schema on home + marketplace pages
- `ab2343e` perf(sitemap): cache plan fetch in allSiteUrls (revalidate=3600)
- `b1fec63` fix(seo): close out 10 remaining Ahrefs Site Audit findings
- `f1f5470` fix(seo): hreflang — separate groups + x-default to en-US

### viralefy_backoffice
- `6660d33` feat(reviews): moderation page for customer reviews
- `f6a7354` feat(i18n): translate entire admin UI to English + locale-aware dates
- `01e90e0` fix(users): credit adjust form labeled USD not R$ (canonical unit)

### viralefy_ops
- `d5f5013` fix(caddy): drop @private X-Robots-Tag override that wasn't applying
- `6404977` feat(caddy): X-Robots-Tag explicit header on www.viralefy.com
- `6dd5bc9` fix(caddy): eliminate redirect chain http://apex → https://www in one hop

---

## 16. Backlog Tier-1 ABERTO (ver RECOMMENDATIONS.md pra plano completo)

1. **Postgres backup automatizado** (pg_dump cron → B2/Storage Box)
2. **JWT RS256** (HS256 atual; vaza secret = vaza tudo)
3. **CI/CD GitHub Actions** (deploy gated por testes)
4. **Status page público** (Grafana hoje é interno)
5. **Anti-fraude velocity rules** (tracking já capturado, só falta enforcement)
6. **Email reputation check** (bloqueio disposable/typos em registers anônimos)

---

## 17. Estrutura de diretórios (resumo)

```
viralefy/
├── viralefy_api/
│   ├── cmd/api/main.go              # wire DI + start crons
│   └── internal/
│       ├── application/              # services + crons
│       ├── domain/                   # entities + repo interfaces
│       ├── infrastructure/
│       │   ├── external/             # email, payment, turnstile, metrics scraper, webhook
│       │   ├── observability/        # slog, OTel, Prometheus
│       │   └── persistence/postgres/ # repos + migrations + seed
│       └── interface/http/           # handlers, middleware, router
├── viralefy_front/
│   ├── src/
│   │   ├── app/                      # App Router (home, [country], legal, marketplace, orders/[id]/review, account, api)
│   │   ├── components/
│   │   ├── i18n/                     # countries, languages, categories, legal
│   │   └── lib/                      # api, auth, jsonld, hreflang, seo-meta, format, tracking, indexnow
│   └── tests/unit/                   # 358 tests
├── viralefy_backoffice/              # 4 PT-regression tests
├── viralefy_ops/
│   ├── bin/                          # viralefy-update, status, logs
│   ├── config/Caddyfile              # 4 site blocks
│   ├── installer/                    # 00-prereqs, 30-secrets, 50-build, 60-systemd
│   └── systemd/                      # hardened units
└── viralefy_archive/
    ├── CONTEXT.md                    # ESTE arquivo
    ├── RECOMMENDATIONS.md            # roadmap 30 items
    ├── COMPLIANCE.md                 # auditoria viva
    └── diretrizes.md                 # normativo
```
