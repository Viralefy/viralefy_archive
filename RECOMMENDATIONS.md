# Viralefy — Recommendations (roadmap 2026-06-05)

Plano de implementação dos 30 items sugeridos no fim da sessão 2026-06-05. Organizado por tier (impacto × urgência). Cada item carrega: justificativa, escopo técnico, arquivos afetados, estimativa, dependências, riscos.

Pareia com `CONTEXT.md` (estado atual) e `diretrizes.md` (normativo).

---

## Tier 1 — Risco operacional / segurança (BLOCK PRD)

### 1. CI/CD GitHub Actions

**Por quê**: hoje `viralefy-update` é destrutivo manual. Push direto pra main pode subir bug que os 454 testes pegariam. Sem gate, qualquer regressão escapa.

**Escopo**:
- `.github/workflows/test.yml` em cada repo (api, front, backoffice):
  - Trigger: `pull_request` + `push: main`
  - Steps: checkout, setup Go 1.23 / Node 20, install deps, run tests, run tsc/go build
  - Required check pra merge
- `.github/workflows/deploy.yml` em main:
  - Trigger: `push: main` após test.yml passar
  - SSH into prod via secret `DEPLOY_SSH_KEY` (mesma chave em /credentials)
  - Run `viralefy-update --yes`
  - Slack/Discord notification via webhook

**Arquivos novos**:
- `viralefy_api/.github/workflows/{test,deploy}.yml`
- `viralefy_front/.github/workflows/{test,deploy}.yml`
- `viralefy_backoffice/.github/workflows/{test,deploy}.yml`
- `viralefy_ops/.github/workflows/{lint,deploy}.yml` (validar Caddyfile + apply remoto)

**Estimativa**: 1 dia (4 yamls + secrets + validar primeira run)

**Risco**: baixo. Pior caso, deploy automático falha e cai no manual atual.

**Secrets necessários (GitHub repo settings)**:
- `DEPLOY_SSH_KEY` (private key OpenSSH em /credentials)
- `DEPLOY_HOST` = `62.238.41.231`
- `DEPLOY_USER` = `root`
- `DEPLOY_WEBHOOK_URL` (Slack/Discord pra notificação)

---

### 2. Postgres backup automatizado

**Por quê**: sem isso um `rm -rf /var/lib/postgresql/data` mata a empresa. HML rodou 6 meses sem backup. Risco existencial.

**Escopo**:
- Script `viralefy_ops/bin/viralefy-backup` (instalado em /usr/local/sbin):
  ```bash
  pg_dump -U viralefy viralefy | gzip > /tmp/viralefy-$(date +%Y%m%d-%H%M).sql.gz
  rclone copy /tmp/viralefy-*.sql.gz remote:viralefy-backups/
  find /tmp -name "viralefy-*.sql.gz" -delete
  ```
- systemd timer `viralefy_ops/systemd/viralefy-backup.timer` (every 6h)
- systemd unit `viralefy-backup.service` (oneshot, runs the script)
- rclone config em `/etc/rclone.conf` com Backblaze B2 (cheap: $0.005/GB/mo) ou Hetzner Storage Box
- Retenção: cron lifecycle no bucket (B2 supports it) ou rclone purge older than 30d

**Arquivos novos**:
- `viralefy_ops/bin/viralefy-backup`
- `viralefy_ops/systemd/viralefy-backup.timer`
- `viralefy_ops/systemd/viralefy-backup.service`
- `viralefy_ops/installer/40-backup.sh` (instala timer + verifica rclone)

**Modificar**:
- `viralefy_ops/installer/30-secrets.sh` — adicionar `B2_KEY_ID`, `B2_APPLICATION_KEY` no .env list
- `viralefy_ops/bin/viralefy-update` — preservar `/etc/rclone.conf` (mesma estratégia do .env)

**Estimativa**: 4h

**Risco**: médio. Testar restore antes de confiar (pg_restore num container limpo + smoke test).

**Custo recorrente**: ~$0.30/mês (60GB de backups por 30 dias = ~$0.30 no B2).

---

### 3. JWT RS256

**Por quê**: hoje HS256 com secret compartilhado entre signing (API) e validação (mesmo serviço — OK por enquanto). Mas se um dia separar microserviços, vazar o secret = vazar tudo. RS256 com chave privada só pra signing e pública pra validação é o padrão.

**Escopo**:
- Gerar par RSA 4096-bit:
  ```bash
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out private.pem
  openssl rsa -pubout -in private.pem -out public.pem
  ```
- Adicionar `JWT_PRIVATE_KEY_PATH` e `JWT_PUBLIC_KEY_PATH` no `internal/config/config.go`
- `internal/infrastructure/auth/jwt.go` (novo):
  - `SignRS256(claims)` lê private key
  - `VerifyRS256(token)` lê public key
- Refactor `AuthService` e `UserAuthService` pra usar
- Migration de tokens existentes: deixar HS256 + RS256 ambos válidos por 7 dias (graceful), depois só RS256
- Endpoint público `/.well-known/jwks.json` pra publicar JWK (futuro multi-service)

**Arquivos novos**:
- `viralefy_api/internal/infrastructure/auth/jwt.go`
- `viralefy_api/internal/infrastructure/auth/jwt_test.go`

**Modificar**:
- `viralefy_api/internal/application/auth_service.go`
- `viralefy_api/internal/application/user_auth_service.go`
- `viralefy_api/internal/config/config.go`
- `viralefy_ops/installer/30-secrets.sh` — gerar par RSA no boot se não existe
- `viralefy_ops/config/Caddyfile` — expose `/.well-known/jwks.json` se necessário

**Estimativa**: 1 dia + 2h de testes

**Risco**: médio-alto. Bug aqui derruba login. Testar com graceful fallback HS256→RS256 antes de remover HS256.

**Lib**: `github.com/golang-jwt/jwt/v5` (já provavelmente no go.mod).

---

### 4. Status page público

**Por quê**: Grafana é interno (admin). Cliente quer transparência quando algo cai. Reduz tickets "está fora do ar?" + sinaliza confiabilidade.

**Escopo (opção A — minimalista própria)**:
- Página `/status` no front:
  - Server component que fetcha `/api/health` da API + Grafana annotation
  - Mostra: API ✅/❌, DB ✅/❌, Email provider, last deploy, incidentes manuais
- `incidents` table no Postgres (admin posta manualmente)

**Escopo (opção B — turn-key)**:
- Self-host [Statping-NG](https://github.com/statping-ng/statping-ng) num subdomínio `status.viralefy.com`
- Caddy redirect + reverse_proxy
- Configurar checks pra cada serviço (HTTP, DB, email API)

**Recomendação**: opção A se simples; opção B se quiser feature-rich (uptime histórico, RSS de incidentes, email subscribers).

**Arquivos novos (A)**:
- `viralefy_front/src/app/status/page.tsx`
- `viralefy_api/internal/interface/http/handlers.go` — `GET /v1/public/incidents` endpoint
- Migration 016: `incidents` table

**Estimativa**: 1 dia (opção A) ou 4h (opção B)

**Risco**: baixo

---

### 5. Anti-fraude velocity rules

**Por quê**: tracking captura tudo (IP, UA, fbclid, client_id) mas ninguém checa. Vai ter abuso de promo, multi-account, scrapper.

**Escopo**:
- `internal/application/fraud_service.go`:
  - `CheckCheckout(ctx, in)` → permita/recuse/flag
  - Rules:
    1. Mesmo `client_id` com order pending < 5min → bloqueia (double-submit prevention)
    2. Mesmo `IP` com 3+ users criados em 24h → flag + admin review
    3. Mesmo `email_domain` (não @gmail, @hotmail) com 10+ users em 7d → flag (corporate spam)
    4. UA com palavras `bot`, `crawler`, `headless` → bloqueia
    5. Country (CF-IPCountry) ≠ country declarado no checkout body → flag (não bloqueia, pode ser VPN legítimo)
- `flagged_orders` table com `reason`, `metadata`, `reviewed_at`
- Backoffice `/fraud` page lista pendentes
- Slack notification quando regra dispara

**Arquivos novos**:
- `viralefy_api/internal/application/fraud_service.go`
- `viralefy_api/internal/domain/fraud.go`
- `viralefy_api/internal/infrastructure/persistence/postgres/fraud_repo.go`
- Migration 016: `flagged_orders` table
- `viralefy_backoffice/src/app/fraud/page.tsx`

**Modificar**:
- `viralefy_api/internal/application/checkout_service.go` — chama `fraud.CheckCheckout` antes de criar order
- RBAC: `fraud:read`, `fraud:moderate` permissions

**Estimativa**: 2 dias

**Risco**: médio (false positives quebram conversão legítima). Modo "shadow" primeiro: roda regras + loga, NÃO bloqueia. Após 1 semana de dados, ativa enforcement em regras com baixo FP.

---

### 6. Email reputation check

**Por quê**: registros anônimos via /checkout aceitam qualquer email. Disposable (10minutemail, tempmail) e typos passam, depois bouncing mata reputation do domain no Resend.

**Escopo**:
- Provider: **Kickbox** (~$0.008/check), **Hunter Verifier**, ou **NeverBounce** ($0.008-0.012)
- `internal/infrastructure/external/email_verify/`:
  - `Service.Verify(ctx, email)` → `{deliverable: bool, role: bool, disposable: bool, score: int}`
- `internal/application/checkout_service.go`:
  - Chama Verify antes de criar user
  - Se disposable=true → recusa com mensagem clara
  - Se deliverable=false E confidence > 80 → recusa
  - Se role=true (info@, support@) → flag mas não recusa
- Cache em Postgres `email_verification_cache` table (TTL 30d) pra economizar API calls

**Arquivos novos**:
- `viralefy_api/internal/infrastructure/external/email_verify/kickbox.go`
- Migration 017: `email_verification_cache`

**Modificar**:
- `viralefy_api/internal/application/checkout_service.go`
- Config: `KICKBOX_API_KEY`

**Estimativa**: 1 dia

**Risco**: baixo. Pode falhar open se API cair (verify retorna unknown → aceita).

**Custo recorrente**: ~$8/mês com 1000 checkouts (Kickbox $0.008/check).

---

## Tier 2 — Receita / conversão (alto ROI)

### 7. Cupom / desconto system

**Por quê**: campanhas (BLACKFRIDAY30, INFLUENCER10, primeira compra) são marketing 101. Sem isso, growth tem ferramenta a menos.

**Escopo**:
- Migration 018:
  ```sql
  CREATE TABLE coupons (
    code TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('percent','flat','free_product')),
    value INTEGER NOT NULL,  -- % se percent, USD-cents se flat
    max_uses INTEGER,
    used_count INTEGER NOT NULL DEFAULT 0,
    valid_from TIMESTAMPTZ,
    valid_until TIMESTAMPTZ,
    min_order_cents INTEGER,
    new_users_only BOOLEAN NOT NULL DEFAULT false,
    plan_categories TEXT[],  -- restringe a categorias específicas
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  CREATE TABLE coupon_redemptions (
    id TEXT PRIMARY KEY,
    coupon_code TEXT NOT NULL REFERENCES coupons(code),
    user_id TEXT REFERENCES users(id),
    order_id TEXT NOT NULL REFERENCES orders(id) UNIQUE,
    discount_cents INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  ```
- `internal/application/coupon_service.go`: ValidateAndApply, MarkUsed
- HTTP: `POST /v1/coupons/validate` (público, retorna desconto preview), `POST /v1/checkout` aceita `coupon_code`
- Backoffice `/coupons` CRUD page
- Permissions: `coupons:read`, `coupons:write`

**Arquivos novos**:
- `viralefy_api/internal/domain/coupon.go`
- `viralefy_api/internal/application/coupon_service.go`
- `viralefy_api/internal/infrastructure/persistence/postgres/coupon_repo.go`
- `viralefy_api/internal/interface/http/coupon_handlers.go`
- `viralefy_backoffice/src/app/coupons/page.tsx`
- `viralefy_backoffice/src/app/coupons/new/page.tsx`
- `viralefy_front/src/components/CouponInput.tsx` (no CheckoutModal)

**Estimativa**: 2 dias (full: migration + service + 2 endpoints + admin UI + frontend input + tests)

**Risco**: médio (cupom é vetor pra abuso — testar edge cases: cumular, expirados, max uses race condition)

---

### 8. Cart abandonment email

**Por quê**: cliente cria invoice pending, sai sem pagar → revenue perdido. Lembrete via email recupera 5-15%.

**Escopo**:
- Cron `AbandonmentCron` seguindo padrão dos 3 existentes:
  - Interval: 30min
  - Query: `SELECT * FROM invoices WHERE status='pending' AND email_sent_at IS NULL AND created_at < NOW() - INTERVAL '60 minutes' LIMIT 100`
  - Pra cada: envia email "Your top-up is waiting" com PaymentURL
  - Update `email_sent_at = NOW()`
- Email template: `BuildAbandonmentEmail(d)` — EN, link pra continuar
- Migration 019: `ALTER TABLE invoices ADD COLUMN abandonment_email_sent_at TIMESTAMPTZ`

**Arquivos novos**:
- `viralefy_api/internal/application/abandonment_cron.go`
- `viralefy_api/internal/application/abandonment_email.go`
- `viralefy_api/internal/application/abandonment_email_test.go`

**Modificar**:
- `viralefy_api/cmd/api/main.go` — Start no boot
- `viralefy_api/internal/infrastructure/persistence/postgres/invoice_repo.go` — `ListReadyForAbandonment`, `MarkAbandonmentEmailSent`

**Estimativa**: 4h

**Risco**: baixo. Já temos pattern.

---

### 9. Subscription / planos mensais

**Por quê**: copy em `i18n/categories.ts:714` já fala em "Cobrança mensal — sem lock-in. Relatório no primeiro dia de cada mês". Falta infra. Receita previsível = valuation × 10.

**Escopo**:
- Migration 020:
  ```sql
  CREATE TABLE subscriptions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    plan_id TEXT NOT NULL REFERENCES plans(id),
    status TEXT NOT NULL CHECK (status IN ('active','paused','cancelled','past_due')),
    current_period_start TIMESTAMPTZ NOT NULL,
    current_period_end TIMESTAMPTZ NOT NULL,
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT false,
    last_invoice_id TEXT REFERENCES invoices(id),
    next_billing_at TIMESTAMPTZ NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cancelled_at TIMESTAMPTZ
  );
  ALTER TABLE plans ADD COLUMN billing_period TEXT;  -- 'one_time' | 'monthly'
  ```
- `internal/application/subscription_service.go`: Create, Cancel, Pause, Resume
- `RenewalCron` (daily): query `next_billing_at <= NOW() AND status='active'` → cria nova invoice → dispara payment
- `dunning` logic: 3 tentativas em 7 dias antes de marcar past_due
- Front: `/account/subscriptions` page
- Backoffice: `/subscriptions` admin view

**Arquivos novos**:
- 8+ arquivos novos (domain, service, repo, cron, handlers, front page, admin page)

**Estimativa**: 4 dias

**Risco**: alto (billing recorrente tem regulação + idempotência crítica + 3rd party risks). Considerar Stripe Billing pra abstrair (custo: 0.4% extra).

---

### 10. Programa de afiliados / referral

**Por quê**: viral compounding + adquire usuário sem CAC pago. Cada user recebe `?ref=USERID`, indicado paga, indicador ganha % no `credit_accounts`.

**Escopo**:
- Já temos `credit_accounts` table! Reusa.
- Migration 021:
  ```sql
  CREATE TABLE referrals (
    id TEXT PRIMARY KEY,
    referrer_user_id TEXT NOT NULL REFERENCES users(id),
    referred_user_id TEXT NOT NULL REFERENCES users(id) UNIQUE,
    first_order_id TEXT REFERENCES orders(id),
    commission_cents INTEGER NOT NULL DEFAULT 0,
    commission_paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  ALTER TABLE users ADD COLUMN referred_by_user_id TEXT REFERENCES users(id);
  ```
- Front: parse `?ref=` no client-side, salva em localStorage, anexa no `tracking` payload do checkout
- Backend: cria `referrals` row quando user_id é gerado (via /register ou /checkout anônimo com ref válido)
- `PaymentReceiver.onOrderPaid`: se é primeira order do user_id E tem referrer → credita 10% do amount no `credit_accounts` do referrer + insere `credit_transactions`
- Front: `/account/refer` mostra link único + dashboard de comissões + lista de pessoas indicadas

**Arquivos novos**:
- ~10 arquivos (domain, service, repo, handler, front page, share component)

**Estimativa**: 2 dias

**Risco**: médio (anti-self-referral: bloquear se IP/device fingerprint mesmo do referrer)

---

### 11. PPP-adjusted pricing

**Por quê**: brasileiro paga mesma coisa que americano hoje. Em India ou Argentina, preço USD canônico é proibitivo. Adjustar pelo poder de compra (PPP) → mais conversão.

**Escopo**:
- `i18n/countries.ts`: adicionar `pppMultiplier: number` por país (US=1.0, BR=0.55, IN=0.30, CH=1.30, etc.)
- Source: [World Bank PPP](https://data.worldbank.org/indicator/PA.NUS.PPP) ou [Numbeo](https://www.numbeo.com)
- `viralefy_front/src/lib/format.ts` — `priceForLocalized(plan, currency, country)`:
  ```ts
  const baseUSD = plan.prices?.USD ?? plan.price_cents/100;
  const localized = baseUSD * country.pppMultiplier;
  // apply currency conversion as before
  ```
- Backend: salvar PPP-applied amount no `orders.amount_cents` (gateway charga este valor)
- Mensagem opcional: "Regional pricing applied — same service, fair price for your market"

**Arquivos novos**: nenhum

**Modificar**:
- `viralefy_front/src/i18n/countries.ts`
- `viralefy_front/src/lib/format.ts`
- `viralefy_api/internal/application/checkout_service.go` (recebe PPP-adjusted amount do front, valida que está dentro de uma faixa razoável: 0.3 ≤ multiplier ≤ 1.5)

**Estimativa**: 1.5 dias (incluindo curadoria de PPP por país)

**Risco**: alto se mal feito (price arbitrage via VPN). Soluções:
- Lock no IP geo do checkout
- Mensagem "shown price valid for visitors from {country}"

---

### 12. A/B testing framework

**Por quê**: hoje vc otimiza por achismo. Sem framework, não tem evidência do que move conversion.

**Escopo**:
- `viralefy_front/src/lib/ab.ts`:
  ```ts
  function variant(experimentKey: string, options: string[]): string {
    const cid = getClientId();
    const hash = hashStr(cid + experimentKey);
    return options[hash % options.length];
  }
  ```
- Estatístico: hash determinístico por `client_id` (já temos tracking), 50/50 ou N/N splits
- Component wrapper: `<ABTest experiment="hero_cta" control={<A/>} variants={[<B/>, <C/>]}/>`
- Tracking: emit conversão evento com `experiment_variant` no `orders.tracking` payload
- Admin: `/experiments` no backoffice — lista experimentos + view de conversão por variant

**Arquivos novos**:
- `viralefy_front/src/lib/ab.ts`
- `viralefy_front/src/components/ABTest.tsx`
- `viralefy_backoffice/src/app/experiments/page.tsx`
- Backend: query `orders.tracking->>'experiment_variant'` GROUP BY pra dashboard

**Estimativa**: 1 dia

**Risco**: baixo

**Casos de uso primeiro mês**:
- Hero copy ("Buy followers" vs "Grow your audience")
- CTA cor (purple vs orange)
- Order de categorias no grid
- Price display: with/without strikethrough fake discount

---

## Tier 3 — Compliance / risco

### 13. GDPR consent banner

**Por quê**: clientes UE + UK obrigatório por GDPR (€20M ou 4% revenue penalty). LGPD BR similar. Hoje nada.

**Escopo**:
- Library: [Klaro!](https://klaro.kiprotect.com/) (open-source, GDPR-compliant out-of-box)
- Cookie banner com toggles por categoria (essential / analytics / marketing)
- Bloquear injection de GA + Meta Pixel até consent
- `viralefy_front/src/components/ConsentBanner.tsx` — wrap em layout.tsx root
- Persist em cookie `consent` JSON

**Arquivos novos**:
- `viralefy_front/src/components/ConsentBanner.tsx`
- `viralefy_front/src/lib/consent.ts`

**Modificar**:
- `viralefy_front/src/app/layout.tsx`
- Scripts de tracking (GA, Pixel) só carrega se `consent.analytics === true`

**Estimativa**: 1 dia

**Risco**: baixo

---

### 14. Manage my data page

**Por quê**: GDPR Article 15 (right to access) + Article 17 (right to erasure) + LGPD Art. 18. 30 dias pra responder.

**Escopo**:
- `/account/privacy` page:
  - Botão "Export my data" → POST `/v1/me/export` → backend gera ZIP com user.json + orders.json + tickets.json + reviews.json + invoices.json
  - Botão "Delete my account" → POST `/v1/me/delete` → marca user com `deleted_at`, anonimiza dados em 30d via cron
- `DeletionCron` (daily): hard-deletes users com `deleted_at < NOW() - 30 days`
- Email confirmation antes de delete (token via link)

**Arquivos novos**:
- `viralefy_front/src/app/account/privacy/page.tsx`
- `viralefy_api/internal/application/data_export_service.go`
- `viralefy_api/internal/application/deletion_cron.go`
- `viralefy_api/internal/interface/http/me_privacy_handlers.go`

**Estimativa**: 2 dias

**Risco**: médio. Cuidado com referential integrity em deletes (invoices que apontam pra user — manter mas anonimizar email/name).

---

### 15. Tax handling por país

**Por quê**: faturar > €10k/ano na UE = registrar IOSS + cobrar VAT (20% IT, 19% DE, 21% NL...). Brazil tem ICMS. Sem isso = sonegação.

**Escopo**:
- `i18n/countries.ts`: `vatRate?: number` + `vatRegime?: 'iva'|'gst'|'icms'|'none'`
- Front: mostra preço net + tax separado no carrinho
- Backend: `orders.tax_cents` column + linha "VAT 20%" no invoice
- Backoffice: relatório mensal por país (export pra contabilidade)

**Arquivos novos**:
- Migration 022: `ALTER TABLE orders ADD COLUMN tax_cents INTEGER NOT NULL DEFAULT 0`
- Backoffice: `/tax-report` page

**Modificar**:
- `viralefy_api/internal/application/checkout_service.go` — calcula tax
- `viralefy_front/src/components/CheckoutModal.tsx` — mostra tax line

**Estimativa**: 3 dias (1 dia código + 2 dias curadoria de rates por país + integração contábil)

**Risco**: alto se mal feito (multa fiscal). Consultar contador antes de ativar.

---

### 16. Refund / dispute admin flow

**Por quê**: hoje nada. Se cliente pede refund, admin teria que mexer no DB. Não escala.

**Escopo**:
- Migration 023: `refund_requests` table
- User: botão "Request refund" em `/orders/[id]` (só pendentes ou disputa)
- Backend: cria `refund_requests` pending → notifica admin via webhook
- Admin: `/refunds` page, approve/deny + automatic reverso no gateway (Woovi/Heleket têm API) + estorno no credit ledger
- Email pro user em cada step (requested, approved, processed)

**Arquivos novos**: 8+ files

**Estimativa**: 2.5 dias

**Risco**: médio (integração com gateway refund API tem edge cases)

---

## Tier 4 — SEO / Growth

### 17. Programmatic SEO de cidades

**Por quê**: hoje 1950 LPs (130 países × 15 categorias). Adicionar top 50 cidades por país (NYC, Rio, Mumbai) → 130 × 50 × 15 = 97.500 LPs. Long-tail "buy followers in {city}" tem busca relevante e baixa concorrência.

**Escopo**:
- `i18n/cities.ts` — top 50 cidades por país com `population`, `name`, `region`
- Routes: `/[country]/[category]/[city]` — extra path segment opcional
- Title/H1 interpolam city
- Hreflang group: city pages têm seu próprio grupo (não confundir com country)
- Sitemap: explode para ~100k URLs

**Arquivos novos**:
- `viralefy_front/src/i18n/cities.ts` (data manual ou via API IPGeolocation)
- `viralefy_front/src/app/[country]/[category]/[city]/page.tsx`

**Estimativa**: 4 dias (1 day code + 3 days data curation)

**Risco**: baixo SEO mas alto custo build (Next.js build com 100k routes = lentidão)

**Alternativa**: dynamic routes + sitemap, não gerar HTML estático

---

### 18. Páginas de comparação

**Por quê**: bottom-funnel keyword "viralefy vs X" tem intent comprar. Hoje 0 LPs.

**Escopo**:
- Pesquisar competitors: InstaFollowers, GoRead, FollowerSky, SocialBoost
- `/compare/[competitor]` page com:
  - Hero: "Viralefy vs {Competitor}: 2026 comparison"
  - Tabela feature × price
  - Pros/cons honestos
  - CTA Viralefy
- JSON-LD: Article + ItemList + ReviewRating

**Arquivos novos**:
- `viralefy_front/src/app/compare/[competitor]/page.tsx`
- `viralefy_front/src/i18n/competitors.ts` — data structure

**Estimativa**: 2 dias

**Risco**: legal (comparar tem que ser honesto + factual). Sem afirmações depreciativas.

---

### 19. Help center / KB público

**Por quê**: tráfego long-tail "is buying followers safe", "do bots delete followers". Reduz tickets de pré-venda.

**Escopo**:
- `/help` index com categorias
- `/help/[slug]` artigos
- Markdown source em `i18n/help/{lang}/{slug}.md`
- JSON-LD Article + breadcrumb
- Search interno (Fuse.js client-side)

**Arquivos novos**:
- `viralefy_front/src/app/help/page.tsx`
- `viralefy_front/src/app/help/[slug]/page.tsx`
- `viralefy_front/src/i18n/help/{en,pt,es,fr,de}/*.md`

**Estimativa**: 3 dias (1 day code + 2 days content curation 30-50 artigos)

**Risco**: baixo

---

### 20. Pricing table comparison

**Por quê**: `/pricing` com tabela lado a lado é página #1 que prospects visitam. Hoje só temos catalog grids.

**Escopo**:
- `/pricing` SSR page
- Tabela por categoria com 5 tiers (Starter / Growth / Pro / Scale / Enterprise)
- Schema PriceSpecification
- CTA por tier

**Arquivos novos**:
- `viralefy_front/src/app/pricing/page.tsx`

**Estimativa**: 1 dia

---

### 21. Case studies com fotos

**Por quê**: social proof maior que reviews simples. "{Customer} hit 100k followers" é narrative.

**Escopo**:
- `/cases/[handle]-{milestone}` (ex: `/cases/marketing_pro-100k`)
- Conteúdo: before/after screenshots, depoimento, plano comprado, timeline
- Schema Article + Person + ImageObject

**Arquivos novos**:
- `viralefy_front/src/app/cases/[slug]/page.tsx`
- `viralefy_front/src/i18n/cases.ts`

**Estimativa**: 2 dias por case study (depois do template, ~30min/case)

---

## Tier 5 — Code quality / DevEx

### 22. E2E com Playwright

**Por quê**: unit + integration via fakes não pega bugs de hidratação, CSP runtime, JS errors. E2E em browser real cobre.

**Escopo**:
- `viralefy_front/tests/e2e/` com Playwright
- Specs: checkout-flow.spec.ts, login-flow.spec.ts, i18n-flow.spec.ts, review-submission.spec.ts
- Rodar em CI (GitHub Actions) + Playwright já tem container Docker pronto
- Headless Chromium + Firefox + Webkit

**Estimativa**: 2 dias (setup + 5 specs)

---

### 23. Storybook

**Por quê**: iterar `CheckoutModal`, `BuyPlanCta` isolado é 10× mais rápido que recarregar Next.js inteiro.

**Escopo**:
- `npx storybook@latest init`
- Stories para: CheckoutModal, BuyPlanCta, TrustSignals, Footer, Header, RecoveryForm, ReviewCard
- Deploy storybook em Vercel/Netlify pra design review

**Estimativa**: 1.5 dias

---

### 24. Zod schemas pra API contracts

**Por quê**: hoje `viralefy_front/src/lib/api.ts` tem tipos TS manuais espelhando Go. Drift inevitável. Bug silencioso.

**Escopo**:
- Backend: gera OpenAPI spec via `swaggo/swag` ou similar
- Front: gera tipos via `openapi-typescript`
- OU: definir schemas em Zod no front + validar runtime

**Estimativa**: 2-3 dias

---

### 25. Sentry/Bugsnag

**Por quê**: hoje erros morrem em `console.error` do browser. Sem visibilidade de erros em prod.

**Escopo**:
- Sentry free tier: 5k events/mês
- `viralefy_front`: `Sentry.init({dsn: process.env.NEXT_PUBLIC_SENTRY_DSN})` em layout.tsx
- `viralefy_api`: `github.com/getsentry/sentry-go`
- Source maps upload no deploy

**Estimativa**: 4h

---

## Tier 6 — Features de produto (longa cauda)

### 26. Order tracking page

**Escopo**: `/orders/[id]/track` com timeline (pending → paid → in_progress → delivering → completed). Reduz "where's my order?" tickets.

**Estimativa**: 1.5 dias

---

### 27. Notification preferences

**Escopo**: `/account/notifications` checkbox grid: canal (email/browser push/telegram) × evento (paid/delivered/refunded/marketing). Migration: `user_notification_prefs` table.

**Estimativa**: 2 dias

---

### 28. WhatsApp opt-in pra updates

**Por quê**: convert >> email pra mercados móveis (BR, IN, MX). WhatsApp Cloud API oficial, ~$0.04/msg.

**Escopo**: número opt-in no checkout, send template via WhatsApp Cloud API quando status muda.

**Estimativa**: 2 dias (incluindo WhatsApp Business verification)

---

### 29. Multi-vendor / marketplace aberto

**Por quê**: revendedor cadastra catálogo próprio + recebe %. Modelo Shopify. Multiplica catálogo 10×.

**Escopo**: vendor accounts, vendor dashboard, escrow, payout system, vendor reviews

**Estimativa**: 3 semanas

**Risco**: alto (complexidade de pricing, taxas, payouts, dispute resolution)

---

### 30. API B2B

**Por quê**: agências querem comprar 100 perfis × 1k followers via API. Faturamento mensal.

**Escopo**: API key system, `/v1/b2b/bulk-checkout`, rate limits maiores, white-label OG images, invoicing mensal consolidado.

**Estimativa**: 1.5 semanas

---

## Roadmap sugerido (4 semanas)

| Semana | Foco | Itens (números desta lista) |
|---|---|---|
| 1 | Risk mitigation | #2 (Postgres backup) · #3 (JWT RS256) · #5+#6 (anti-fraude + email check) |
| 2 | Receita | #7 (cupom) · #8 (cart abandonment) · #4 (status page) |
| 3 | Compliance + CI | #13 (GDPR banner) · #14 (manage data) · #1 (CI/CD) |
| 4 | Growth | #17 (cidades programmatic) · #18 (comparações) · #22 (Playwright) |

Items de maior impacto/risco (#9 subscriptions, #15 tax, #29 multi-vendor) — agendar separado, precisam mais escopo.

---

## Decisão recomendada

Implementar nessa ordem:
1. **#2 Postgres backup** (deploy hoje, 4h, dorm em paz)
2. **#8 Cart abandonment** (cron, 4h, segue pattern dos existentes)
3. **#7 Cupom system** (2 dias, ROI imediato pra primeira campanha)
4. **#1 CI/CD** (1 dia, blinda regressão)
5. **#3 JWT RS256** (1 dia, security debt)

Depois reavalia com base no que move o ponteiro.
