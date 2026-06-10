# Viralefy — CONTEXT.md (snapshot pra compactação de contexto)

**Última atualização:** 2026-06-10 (PHASE-9 closed + Coraza Block + ops hardening + SLOs/alerting + error budget dashboard ativo em prod)

Este arquivo é o "leia primeiro" pra qualquer próxima sessão. Resume estado factual sem narrativa.

---

## 1. Plataforma em 60s

Marketplace de engajamento Instagram/TikTok, **prod live em https://www.viralefy.com**, faturando. 130 países × 47 idiomas × 12 categorias ativas. USD/USDT canonical, multi-moeda display.

**VPS única:** Debian 13 trixie · 8c/16GB · 134GB livres · `root@62.238.41.231`.

**Faturamento ativo (gateways):**
- **Stripe** rk_live_ — webhooks corretos em `api.viralefy.com/v1/webhooks/stripe`
- **Heleket** crypto auto, USDT settlement
- **AbacatePay** PIX dinâmico (cliente cadastrou)
- ~~manual_pix~~ desativado (active=false)
- ~~woovi~~ inactive

**Autenticação:** JWT RS256 (HS256 legado em dual-sign), 2FA admin obrigatório, 2FA user opt-in, `kid=vfCOltLYjII` compartilhado entre legacy + core + auth.

---

## 2. Acesso

| Recurso | URL | Credencial |
|---|---|---|
| Storefront | https://www.viralefy.com | — |
| Backoffice | https://admin.viralefy.com | `viralefy@gmail.com` / `VfIULsiPGXKZGjGfu2yn!` (superadmin 2FA enrolled) |
| API | https://api.viralefy.com | Bearer RS256 |
| Observability | https://obs.viralefy.com | `admin` / `6FU6jXSmzJlrPSCBJ6JNprW5dqMYCO1l` |
| SSH | `root@62.238.41.231` | `awk '/BEGIN OPENSSH/,/END OPENSSH/' /media/sonne/Archives/projects/viralefy/credentials > /tmp/vf-ssh.key && chmod 600 /tmp/vf-ssh.key` |
| Postgres | local na VPS | senha em `/etc/viralefy/.env` |
| GitHub | https://github.com/Viralefy | 10 repos públicos |

---

## 3. Arquitetura PHASE-9 — CUTOVER 100% ATIVO em prod

```
INTERNET
   ↓
Caddy 2.11.3 + Coraza WAF + OWASP CRS 4.10 (DetectionOnly + audit JSON ativo)
   ├── www → viralefy-front (Next 15, :3000)
   ├── admin → viralefy-backoffice (:3001)
   ├── obs → Grafana (:3030) [5 dashboards Viralefy: revenue/payments/behavior/reliability/slo + 37 alert rules (11 legacy + 26 SLO/infra)]
   └── api → ROTEAMENTO POR PATH:
        │
        ├── /v1/plans*, /v1/categories*, /v1/currencies*, /v1/status*,
        │   /v1/country-ppp*, /v1/tax-rates*  → dispatcher :8090 → core :8084
        ├── /.well-known/jwks.json            → dispatcher :8090 → auth :8083
        ├── /v1/auth/*                        → dispatcher :8090 → auth :8083
        ├── /v1/me/* (38 rotas)               → dispatcher :8090 → core :8084
        ├── /v1/admin/* (52+ rotas)           → dispatcher :8090 → core :8084
        ├── /v1/checkout                      → dispatcher :8090 → core :8084
        ├── /v1/webhooks/{stripe,heleket,...} → payments :8081 (direto, Caddy-rewrite)
        ├── /internal/*                       → 404 (defense-in-depth na borda)
        └── /health, /v1/auth-legacy (não usado) → api LEGACY :8080 (dead code)

viralefy-api LEGACY :8080 ainda ativo mas NÃO recebe tráfego de produção.
Cron StripeReconcile roda em paralelo (idempotente). Aguarda 14d soak
sem regressão pra ser parado e arquivado.

Rollback: comentar `handle` blocks no Caddyfile + reload = 0-downtime.
```

**Auth interno entre services:** `INTERNAL_SHARED_SECRET` em `X-Internal-Token`. Loopback-only.

**Object storage:** MinIO Docker `/var/lib/viralefy-storage/`, S3-compat (proofs bucket privado + public). R2-ready.

---

## 4. 10 Repositórios (Viralefy GitHub org)

| Repo | Função | Estado |
|---|---|---|
| `viralefy_api` | Monolito Go LEGACY (port 8080) | Live, será aposentado em cutover |
| `viralefy_payments` | Providers + webhooks (8081) | Live |
| `viralefy_sender` | Email + telegram + outbox (8082) | Live |
| `viralefy_front` | Next.js storefront | Live |
| `viralefy_backoffice` | Next.js admin panel | Live |
| `viralefy_ops` | systemd + installer + Caddy + CLIs | Live |
| `viralefy_archive` | docs + memory (este repo) | Live |
| **`viralefy_core`** | **Motor Go (port 8084)** — sucessor do api | **Deployed paralelo, paridade 100%** |
| **`viralefy_auth`** | **Identidade Go (port 8083)** — JWT + 2FA + hot-set | **Deployed paralelo** |
| **`viralefy_dispatcher`** | **Borda Rust (port 8090)** — sanitiza + proxy + JWT verify | **Deployed paralelo** |

---

## 5. Stack rodando em prod (mem usage real)

| Port | Service | Binary | Mem | Linguagem |
|---|---|---|---|---|
| 8080 | viralefy-api LEGACY | 35MB | 29MB | Go |
| 8081 | viralefy-payments | - | 7MB | Go |
| 8082 | viralefy-sender | - | 13MB | Go |
| 8083 | **viralefy-auth** | 11MB | **7MB** | Go |
| 8084 | **viralefy-core** | 24MB | 14MB | Go |
| 8090 | **viralefy-dispatcher** | **7.2MB** | **2MB** | **Rust** |
| — | Caddy + Coraza | 54MB | ~100MB | Go + WAF |

**Total RAM em uso:** ~170MB de 16GB disponíveis.

---

## 6. Schema DB (39 migrations aplicadas)

Migration tracker tipo Laravel — tabela `schema_migrations` com checksum SHA256, auto-backfill detecta prod legado, `Seed()` opt-in (não auto em boot). Última: **039_auth_tokens** (refresh_tokens + revoked_jtis + password_resets).

**Núcleo:**
- users, admins, roles, role_permissions
- plans, plan_prices, categories
- orders, order_refunds, order_proofs
- payment_gateways, stripe_events_processed
- credit_accounts, credit_transactions, invoices
- profiles, subscriptions

**Tracking:**
- user_events, user_journeys, ab_experiments, ab_assignments, ab_events

**Segurança & PHASE-9:**
- admin_2fa, user_2fa
- **refresh_tokens** (rotação encadeada)
- **revoked_jtis** (hot-set + LISTEN/NOTIFY no canal `revoked_jtis_inserted`)
- **password_resets** (single-use TTL 1h)
- audit_log, idempotency_keys, user_deletion_requests

**Features:**
- coupons, reviews, tickets, ticket_messages, referral_rewards
- api_keys, currencies, country_ppp, tax_rates
- email_events, email_reputation, fraud_signals, fraud_blocks
- vendors, user_contact

---

## 7. Auth dual-sign (RS256 + HS256 legado)

- **Mint:** todos services emitem RS256 com `kid=vfCOltLYjII`
- **Verify:** RS256 primário + HS256 fallback (janela de migração 7d)
- **2FA:** TOTP RFC 6238 + AES-256-GCM secret encryption + bcrypt backup codes
- **Hot-set revogação:** tabela `revoked_jtis` + `pg_notify('revoked_jtis_inserted', jti)` consumido pelo dispatcher Rust via LISTEN/NOTIFY (5s polling fallback)
- **Refresh tokens:** rotação encadeada (anti-replay), TTL 30d, replay de revogado → force-logout do subject inteiro

---

## 8. Env vars críticas em `/etc/viralefy/.env`

**Presentes em prod:**
- `DATABASE_URL`, `PORT=8080` (legacy), `BIND_HOST=127.0.0.1`
- `JWT_SECRET`, `JWT_PRIVATE_KEY_PATH=/etc/viralefy/jwt-rs256.pem`
- `TWOFA_ENCRYPTION_KEY` (32 bytes hex)
- `INTERNAL_SHARED_SECRET` (32 bytes hex, compartilhado entre todos services)
- `RESEND_API_KEY`, `RESEND_FROM=contato@viralefy.com`
- `TURNSTILE_SECRET_KEY` (anti-bot ativo)
- `STORAGE_ACCESS_KEY` / `STORAGE_SECRET_KEY` (MinIO)
- `PAYMENTS_INTERNAL_URL=http://127.0.0.1:8081`
- `SENDER_INTERNAL_URL=http://127.0.0.1:8082`

**Env do core (deploy paralelo) — sobrescritas no systemd unit:**
- `CORE_PORT=8084` (precedência sobre `PORT=8080`)
- `BIND_HOST=127.0.0.1`

**Env do auth — no systemd unit:**
- `VAUTH_BIND_ADDR=127.0.0.1:8083`
- `VAUTH_ACCESS_TOKEN_TTL=15m`, `VAUTH_REFRESH_TOKEN_TTL=720h`

**Env do dispatcher Rust — no systemd unit:**
- `VAPI_BIND_ADDR=127.0.0.1:8090`
- `VAPI_CORE_URL=http://127.0.0.1:8084`
- `VAPI_AUTH_URL=http://127.0.0.1:8083`
- `VAPI_PAYMENTS_URL=http://127.0.0.1:8081`
- `VAPI_SENDER_URL=http://127.0.0.1:8082`
- `VAPI_JWKS_CACHE_TTL_SECS=60`, `VAPI_REVOKED_POLL_SECS=5`

**Opt-in pendentes (vazias):**
- `SENTRY_DSN` / `NEXT_PUBLIC_SENTRY_DSN`
- `TELEGRAM_BOT_TOKEN` / `TELEGRAM_ADMIN_CHAT_ID`
- `ADMIN_WEBHOOK_URL` (Slack/Discord)

---

## 9. Operação day-a-day

| Ação | Comando |
|---|---|
| Deploy | `ssh root@62.238.41.231 'viralefy-update --yes'` (zero-downtime, 2min, smoke automático) |
| Smoke | `ssh root@62.238.41.231 'viralefy-smoke'` (3 legacy + 3 PHASE-9 + 2 endpoint tests) |
| Status | `ssh root@62.238.41.231 'viralefy-status'` |
| Logs core | `journalctl -u viralefy-core -f` |
| Logs auth | `journalctl -u viralefy-auth -f` |
| Logs dispatcher | `journalctl -u viralefy-dispatcher -f` |
| Logs Coraza WAF | `journalctl -u caddy -f \| grep coraza` |
| Migrate status | `sudo -u viralefy-core /usr/local/sbin/viralefy-core migrate status` (env file readable required) |
| Restore DB | vide RUNBOOK.md (drill validated 2026-06-08) |

---

## 10. Coraza WAF — DetectionOnly em prod (audit log ativo após fix 06-10)

- Buildado via `xcaddy build v2.11.3 --with github.com/corazawaf/coraza-caddy/v2`
- OWASP CRS 4.10.0 em `/etc/caddy/coraza/crs/` (46 rule files)
- `SecRuleEngine DetectionOnly`
- **`SecAuditLog /var/log/caddy-waf/audit.log` ATIVO** (estava comentado; fix 06-10)
- `SecAuditLogFormat JSON` + `SecAuditLogRelevantStatus ".*"` (logs todos detect mesmo com 200 OK upstream)
- Pre-stage exclusões em `/etc/caddy/coraza/coraza-crs-exclusions.conf` (Stripe webhook sig + /v1/reviews markdown body)

**Validado em prod com payloads reais:**
- SQLi `?q=1 OR 1=1--` → rule `942100` libinjection detectada
- XSS `?q=<script>alert(1)</script>` → 4 rules `941xxx` detectadas + audit log popula 6278 bytes

**Re-audit 2026-06-10 07:40 UTC (24h, 16.474 req / 2.274 IPs / 4.234 URIs):**
- 27 warnings, **todos do IP do próprio host** (smoke tests do operador). Nenhum hit externo.
- 1 FP estrutural real identificado: rule `942100` libinjection em `ARGS:json.password` no `/v1/auth/user/register` (password tipo gerador `HotSetTest123!@#` bate fingerprint `novc`, score 5 = limiar). Risco alto pra qualquer senha de password manager.
- Tentativa de exclusão `900600` (phase 1, `ctl:ruleRemoveTargetById=942100;ARGS:json.password`) NÃO funcionou — provável que o JSON body só esteja parseado em phase 2. Rolledback.
- **Decisão: NO FLIP.** Soak continua até fix da exclusão password + 24-48h de validação. Detalhes em `CORAZA-SOAK-STATUS.md`.

**Plano revisado:** fix exclusion (phase 2 ou `ctl:ruleEngine=Off` escopado por URI) → re-test → soak 24-48h → flip alvo 2026-06-13.

**Update 2026-06-10 12:20 UTC — Coraza SecRuleEngine On ATIVO**:
- Causa raiz do warning não-bloqueando: CRS `SecDefaultAction phase:1/2,log,auditlog,pass`. O `pass` sobrescreve `deny` das rules individuais.
- Fix: `SecDefaultAction phase:1/2 → deny,status:403` + `systemctl restart caddy` (não reload)
- Password FP exclusion `id:900601` phase 2 funcional (commit ops@20f38f7)
- HTTP methods exclusion `id:900700`: PUT/PATCH/DELETE agora liberados (rule 911100 do CRS bloqueava — backoffice mutations quebradas; commit ops@76b6e0c)
- E2E validado: 5/5 SQLi/XSS → 403, register password password-manager → 201, GETs → 200, métodos REST OK

**Estado atual: 5 critérios "Fase 9 100% pronta" cumpridos.**

---

## 11. Documentos no archive (referência)

| Doc | Conteúdo |
|---|---|
| **CONTEXT.md** | este arquivo |
| **CHECKLIST.md** | done + pending + priorizado |
| INDEX.md | snapshot histórico das fases (compatibilidade) |
| STATUS-CHECKLIST.md | checklist longo (~250 items, histórico) |
| PHASE-7-PLAN.md | plano fase 7 (storage, 2FA, dashboards) |
| PHASE-8-MICROSERVICES.md | plano fase 8 (carve-out micros) |
| **PHASE-9-ARCHITECTURE.md** | plano fase 9 (1056 linhas, revisado adversarialmente 12 críticas) |
| MICROSERVICES-OPS.md | runbook ops dos 3 binários legacy |
| RUNBOOK.md | playbook prod (incidents, restore drill) |
| COMPLIANCE.md | GDPR, LGPD, EU VAT |
| ROADMAP.md | histórico de fases 0-7 entregues |
| RECOMMENDATIONS.md | auditoria técnica original |
| diretrizes.md | técnicas + convenções |
| AGENTS.md | instruções pra subagentes |
| memory/ | auto-memory (symlinkada de `~/.claude/.../memory/`) |

---

## 12. Pendências críticas (vide CHECKLIST.md pra completa)

**Cliente precisa fornecer:**
- Telegram bot TOKEN + CHAT_ID (opcional)
- Sentry DSN (opcional)
- Slack/Discord webhook (opcional)

**Engineering:**
- Strangler cutover PHASE-9 por bucket (public → user/me → admin → checkout)
- 14 dias Coraza DetectionOnly → tuning → Block
- Object storage migration proofs base64 → MinIO keys (parcial)
- Grafana contact points + 4 dashboards
- Sentry source maps no CI
- Renovate GitHub App: instalar em https://github.com/apps/renovate (configs já em todos os 10 repos via preset `viralefy_ops/renovate-config.json` — vide `RUNBOOK-RENOVATE.md`)

**Decisão de produto:**
- Multi-vendor settlement model
- WhatsApp provider real (Meta vs Twilio)
- API B2B billing tier

---

## 13. Como começar uma nova sessão

1. Ler **este arquivo** (CONTEXT.md) — entender estado atual
2. Ler **CHECKLIST.md** — ver done + pendências priorizadas
3. Ler memória persistente em `~/.claude/.../memory/MEMORY.md`
4. Confirmar prod saudável: `ssh root@62.238.41.231 'viralefy-smoke'`
5. Escolher próxima task da CHECKLIST priorizada

**Convenção:** ao fechar uma task, atualizar CONTEXT.md (se mudou arquitetura) + CHECKLIST.md (sempre) + commit no archive.
