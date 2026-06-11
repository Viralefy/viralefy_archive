# RUNBOOK — Cloudflare WAF migration (Caddy+Coraza → Cloudflare Business)

**Status:** DOCUMENTAÇÃO. Nenhuma ação em prod até decisão explícita do cliente.
**Last review:** 2026-06-11.
**Owner ops:** infra@viralefy.
**Janela mínima entre decisão e go-live:** 7 dias corridos (DNS TTL + soak rules + smoke).

> **Posição honesta antes de tudo:** hoje Caddy+Coraza está em soak DetectionOnly
> (vide `CORAZA-SOAK-STATUS.md`). Não temos 30 dias clean ainda. Este runbook só
> deve ser executado APÓS Coraza completar 30 dias em `SecRuleEngine On` sem
> regressão organica — caso contrário a migração mascara um problema que vamos
> reproduzir em qualquer WAF gerenciado.

---

## TL;DR — recomendação

| Cenário | Recomendação |
|---|---|
| Hoje (Coraza ainda em soak) | **NÃO migrar.** Termina o soak primeiro. |
| Daqui 3 meses (Coraza estável, tráfego < 1M req/dia) | **NÃO migrar.** Coraza custa 100 MB RAM + ~10h/mês operator. Cloudflare Business custa US$2.400/ano. Não compensa. |
| Quando tráfego > 5M req/dia OU sofrermos primeiro DDoS L7 sério | **MIGRAR.** A partir desse volume, CDN + DDoS protection paga sozinho. |
| Se compliance LGPD/PCI exigir WAF gerenciado com SOC2/ISO27001 | **MIGRAR.** Coraza não tem certificações de terceiros. |

**Decisão atual:** manter Caddy+Coraza. Este runbook fica engatilhado pro
próximo gate de tráfego/incidente. Revisão obrigatória a cada 6 meses.

---

## 1. Pré-requisitos

### 1.1 Conta + plano

- **Cloudflare Business** — US$200/mês = US$2.400/ano. WAF managed rules,
  custom rules ilimitadas, Bot Fight Mode, image optimization, 25 page rules.
- **NÃO basta Pro** (US$25/mês): managed rules são limitadas, sem custom WAF
  rules, sem Bot Management avançado, sem certificados upload customizados.
- **Enterprise (cotado):** só se precisar Authenticated Origin Pulls com cert
  customizado, Argo Smart Routing ou compliance addons. Não recomendado pra
  Viralefy nesse estágio.

### 1.2 Credenciais e acessos

- Conta Cloudflare com 2FA TOTP obrigatório (admin + ops backup).
- **API token escopo mínimo:**
  - `Zone:Edit` no zone `viralefy.com`
  - `Zone:DNS:Edit` no zone `viralefy.com`
  - `Zone:WAF:Edit` no zone `viralefy.com`
  - `Account:Account Settings:Read` (pra verificar plan)
  - **NÃO usar Global API Key.** Sempre token escopado.
- Acesso ao registrar atual do domínio (verificar em `whois viralefy.com` —
  hoje aponta pra registrar BR ou .com internacional, confirmar antes).
- Acesso SSH `root@62.238.41.231` pra mudar Caddy config e iptables.
- Comunicação com usuários: banner 48h antes em `www.viralefy.com` + email
  pros admins de loja.

### 1.3 Inventário do estado atual (snapshot pra rollback)

Capturar em `/etc/viralefy/migration-snapshot-YYYYMMDD/`:

```bash
mkdir -p /etc/viralefy/migration-snapshot-$(date +%Y%m%d)
cd /etc/viralefy/migration-snapshot-$(date +%Y%m%d)

# DNS atual (capturar TODOS os records)
for sub in @ www admin api obs cdn; do
  dig +noall +answer "${sub}.viralefy.com" A AAAA CNAME MX TXT
done > dns-current.txt

# Caddy
cp /etc/caddy/Caddyfile caddy.bak
cp -r /etc/caddy/coraza coraza.bak

# iptables atual
iptables-save > iptables.bak
ip6tables-save > ip6tables.bak

# Cert atual (Caddy auto Let's Encrypt)
cp -r /var/lib/caddy/.local/share/caddy/certificates caddy-certs.bak

# TTL atual de cada record (pra calcular janela de propagação)
dig +noall +answer +ttlid viralefy.com NS
```

---

## 2. Phase 0 — Prep (Day 0, no-impact)

### 2.1 Catalog de subdomínios em produção

Hoje (conferido em `Caddyfile`):

| Subdomain | Upstream | Notas |
|---|---|---|
| `viralefy.com` (apex) | 301 → `www.` | redir Caddy, single hop |
| `www.viralefy.com` | front Next.js :3000 | canônico, SEO target |
| `admin.viralefy.com` | backoffice Next.js :3001 | RBAC, sem GTM |
| `api.viralefy.com` | Caddy → dispatcher :8090 | WAF Coraza atual |
| `obs.viralefy.com` | Grafana :3030 | acesso restrito IP allowlist atual |
| `cdn.viralefy.com` (se existir) | bucket MinIO/S3 | confirmar antes |

> **Action:** rodar `dig +short` em cada um e validar contra a lista acima.
> Qualquer subdomain extra (preview/staging) precisa ser importado.

### 2.2 Baseline de métricas (pra detectar regressão pós-cutover)

Capturar 7 dias antes do cutover via Grafana:

- p50/p95/p99 latência por endpoint top-20.
- Error rate 5xx por endpoint.
- Requests/s por subdomínio.
- WAF blocks atual (após Coraza estabilizar `On`).
- TLS handshake duration p95.

Exportar JSON via Grafana API e arquivar em
`migration-snapshot-YYYYMMDD/grafana-baseline.json`.

### 2.3 Conta Cloudflare de teste

- Criar zone trial em domínio descartável (ex: `viralefy-cf-test.com` ou
  subdomínio já existente apontando pra IP de homologação).
- Ativar Business plan no trial OU usar segundo zone com plan separado.
- Testar TODA a config WAF antes em zone trial. **Não testar em prod.**

---

## 3. Phase 1 — Cloudflare zone setup (Day 1, no-impact em prod)

> **Critério "no-impact":** nenhum DNS público muda. Cliente continua
> resolvendo viralefy.com pelo DNS atual. Cloudflare fica em "Pending NS
> change" sem efeito.

### 3.1 Adicionar domínio

1. Dashboard Cloudflare → Add a Site → `viralefy.com` → Business plan.
2. Cloudflare auto-importa records via scan. **Conferir 1:1** contra
   `dns-current.txt` capturado em Phase 0. Records ausentes (subdomínios
   atrás de wildcard, TXT SPF/DKIM/DMARC) devem ser adicionados manualmente.
3. **Manter todos os records como DNS-only (nuvem cinza)** nesta fase.
   Orange cloud (proxy ativo) só na Phase 5 após validação.

### 3.2 SSL/TLS mode

- **Encryption mode:** Full (Strict). Caddy já entrega cert Let's Encrypt
  válido — Cloudflare valida origin cert.
- **Edge Certificate:** Universal SSL (incluso). Adicional: Advanced Cert
  com TLS 1.3 only se compliance pedir.
- **Min TLS Version:** 1.2 (1.3 quebraria clientes antigos do BR).
- **HSTS:** **NÃO ativar no Cloudflare ainda.** Caddy já emite header HSTS
  com preload. Duplicar gera conflito de policy em rollback.

### 3.3 DNS verification

Cloudflare exige confirmação por TXT antes de ativar zone. Esperar status
"Active" no dashboard antes de prosseguir pra Phase 2.

### 3.4 Rollback Phase 1

Trivial: deletar o zone no dashboard. Nenhum impacto em prod (NS não
mudaram).

---

## 4. Phase 2 — Cloudflare WAF rules setup (Day 2, em Detection mode)

> **Todas as regras criadas nesta fase ficam em `Log` action, não `Block`.**
> Validar 48h de tráfego shadow antes de promover qualquer regra pra block.

### 4.1 Managed Rules

- Ativar **Cloudflare Managed Ruleset** — equivalente operacional ao OWASP
  CRS que Coraza roda hoje. Sensitivity: Medium (paranoia ~2 do CRS).
- Ativar **Cloudflare OWASP Core Ruleset** — gêmeo do que já roda em Coraza.
  Score threshold: 25 (equivalente a anomaly 5 do CRS atual).
- **NÃO ativar** Exposed Credentials Check no plano Business (só Enterprise).
- Action default de TUDO: `Log` (não Block) por 48h mínimo.

### 4.2 Custom rules — replicar exclusões Coraza

Cada exclusion atual em `coraza-crs-exclusions.conf` precisa de equivalente
Cloudflare (Custom Rule ou Managed Rule Exception):

#### 4.2.1 Stripe webhook signature
```
(http.request.uri.path eq "/v1/webhooks/stripe")
→ Skip → All Managed Rules
```
Justificativa idêntica ao Coraza: payload é HMAC-verificado pelo handler;
WAF na borda só adiciona ruído.

#### 4.2.2 Password fields em auth (a regra que travou o flip pra `On`)
```
(http.request.uri.path contains "/v1/auth/" and http.request.method eq "POST")
→ Skip → Managed Rule IDs equivalentes a 942100/942110 (libinjection SQLi)
```
**Em Cloudflare a exclusão é por rule ID + scope, não por ARGS:json.password.**
Cloudflare não permite excluir um campo JSON específico — só rule inteira no
path. Trade-off: perdemos granularidade. Mitigação: confiar na bcrypt no
handler (já é o caso) e em rate limit de auth (já existe in-memory 10/15min).

#### 4.2.3 Reviews (markdown user-generated)
```
(http.request.uri.path contains "/v1/reviews" and http.request.method eq "POST")
→ Skip → IDs equivalentes a 941100/941110/941160/941390 (XSS) + 942100 (SQLi)
```

#### 4.2.4 REST methods em rotas admin/me
```
(http.request.uri.path contains "/v1/admin/" or http.request.uri.path contains "/v1/me/")
and http.request.method in {"PUT" "PATCH" "DELETE"}
→ Skip → Method validation rules (920100 family equiv)
```

#### 4.2.5 Tracking/UTM em checkout (lesson learned do incidente UTMs)
```
(http.request.uri.path eq "/v1/checkout" or http.request.uri.path contains "/v1/auth/")
and len(http.request.uri.query) > 0
→ Skip → 932xxx (LFI heuristics on query) e 941xxx PL2 only
```

### 4.3 Rate limiting

Hoje: tower_governor no dispatcher Rust = 30 burst + 1/s per IP.

Cloudflare Rate Limiting (Business inclui 10 regras):

| Regra | Threshold | Window | Action |
|---|---|---|---|
| `/v1/auth/*` POST | 10 | 15min | Block 1h |
| `/v1/checkout` POST | 5 | 1min | Challenge |
| `/v1/admin/*` qualquer | 60 | 1min | Block 5min |
| Global per IP | 300 | 1min | JS Challenge |

**Manter tower_governor no dispatcher como fallback.** Defense in depth.

### 4.4 Bot Management

- **Bot Fight Mode:** ON (incluso Business). Bloqueia bots conhecidos.
- **Super Bot Fight Mode:** definite bots → Block, likely automated → Managed
  Challenge.
- **Allowlist obrigatória:** Googlebot, Bingbot (hoje 66.249.68.x trafega
  organic, vide CORAZA-SOAK-STATUS), Stripe webhooks (IPs em
  https://stripe.com/files/ips/ips_webhooks.json).

### 4.5 Validação Phase 2

```bash
# Simular tráfego contra zone de teste (DNS-only, hosts file aponta pro CF edge IP)
curl -H "Host: api.viralefy.com" \
     --resolve api.viralefy.com:443:<CF_EDGE_IP> \
     https://api.viralefy.com/v1/plans

# Verificar logs em Cloudflare → Security → Events
# Esperado: 0 blocks de tráfego legítimo, todos managed rule hits em "Log"
```

### 4.6 Rollback Phase 2

Mudar action de cada regra pra `Skip` ou desativar. Records ainda DNS-only,
tráfego prod intocado.

---

## 5. Phase 3 — Caching strategy (Day 2, ainda DNS-only)

### 5.1 Page Rules / Cache Rules

| Path pattern | Cache | TTL edge | Notas |
|---|---|---|---|
| `/v1/plans*` | Standard | 5min | Public list, mudanças raras |
| `/v1/categories*` | Standard | 1h | Quase estático |
| `/v1/currencies*` | Standard | 1h | Quase estático |
| `/v1/country-ppp*` | Standard | 6h | Lookup table |
| `/v1/tax-rates*` | Standard | 1h | |
| `/.well-known/jwks.json` | Standard | 5min | Crítico não cachear demais (key rotation) |
| `/_next/static/*` | Standard | 1y | Hashed asset, immutable |
| `/v1/me/*` | **Bypass** | — | Per-user, NUNCA cache |
| `/v1/admin/*` | **Bypass** | — | RBAC, NUNCA cache |
| `/v1/checkout*` | **Bypass** | — | Idempotency-Key sensible |
| `/v1/auth/*` | **Bypass** | — | Auth flow |
| `/v1/webhooks/*` | **Bypass** | — | Provider deliveries |
| `/internal/*` | **Block 404 na borda** | — | Espelha Caddy atual |

### 5.2 Cache Rules — fail-safe headers

Forçar bypass via cookie de sessão:
```
(http.cookie contains "jwt" or http.request.headers["authorization"] != "")
→ Cache: Bypass
```

Isso impede vazamento de response autenticada pro cache compartilhado.

### 5.3 Rollback Phase 3

Cache rules: desativar todas. Cloudflare default = respeitar `Cache-Control`
do origin. Hoje Caddy não emite `Cache-Control: public`, então default é
no-cache em quase tudo.

---

## 6. Phase 4 — Origin protection (Day 3, ainda DNS-only)

> **Objetivo:** quando trocarmos DNS pro Cloudflare, impedir que ataque
> bypass-CF resolva IP direto e bata na VPS. Hoje `62.238.41.231` é trivial
> de descobrir (passive DNS history).

### 6.1 Authenticated Origin Pulls

Cloudflare Business inclui cert AOP padrão.

1. Cloudflare dashboard → SSL/TLS → Origin Server → Authenticated Origin
   Pulls → Enable (zone level).
2. Download cert CF (`origin-pull-ca.pem`) — pinning na config Caddy.
3. Caddy config (em `api.viralefy.com` e `www.viralefy.com`):
   ```caddyfile
   tls {
     client_auth {
       mode require_and_verify
       trust_pool file /etc/caddy/cloudflare-aop.pem
     }
   }
   ```
4. **Atenção:** AOP só funciona quando record está orange-cloud (proxied).
   Records gray-cloud (admin/obs se mantiver direto) continuam acessíveis
   sem cert client.

### 6.2 IP allowlist no firewall

Hoje iptables atual aceita 80/443 de 0.0.0.0/0. Após Phase 5 cutover, fechar
pra apenas Cloudflare IPs.

**NÃO aplicar antes do cutover** — quebra acesso direto pro debug.

Script preparado pra aplicar SOMENTE após Phase 5:

```bash
#!/bin/bash
set -euo pipefail

# Snapshot atual
iptables-save > /root/iptables.pre-cf-lockdown.bak

# Fetch CF ranges (live, autoritativo)
CF_V4=$(curl -fsS https://www.cloudflare.com/ips-v4)
CF_V6=$(curl -fsS https://www.cloudflare.com/ips-v6)

# Nova chain
iptables -N CF_ONLY 2>/dev/null || iptables -F CF_ONLY
ip6tables -N CF_ONLY 2>/dev/null || ip6tables -F CF_ONLY

# Allow SSH (NÃO bloquear — operator backup)
iptables -A CF_ONLY -p tcp --dport 22 -j ACCEPT

# Allow CF v4
for cidr in $CF_V4; do
  iptables -A CF_ONLY -p tcp -m multiport --dports 80,443 -s "$cidr" -j ACCEPT
done

# Allow CF v6
for cidr in $CF_V6; do
  ip6tables -A CF_ONLY -p tcp -m multiport --dports 80,443 -s "$cidr" -j ACCEPT
done

# Drop everything else nas portas web
iptables -A CF_ONLY -p tcp -m multiport --dports 80,443 -j DROP
ip6tables -A CF_ONLY -p tcp -m multiport --dports 80,443 -j DROP

# Hook na INPUT
iptables -I INPUT -j CF_ONLY
ip6tables -I INPUT -j CF_ONLY

echo "Lockdown applied. Rollback: iptables-restore < /root/iptables.pre-cf-lockdown.bak"
```

### 6.3 Cloudflare Tunnel (opcional, alternativa ao 6.2)

`cloudflared` cria túnel reverse — elimina IP público completamente.

- Pró: VPS sem IP público exposto, ataque direto impossível.
- Contra: latência extra (~5ms BR), dependência de runtime adicional,
  systemd unit nova, complica blue/green deploys.

**Não recomendado** pra Viralefy nesse momento — IP allowlist (6.2) entrega
99% do benefício com 10% da complexidade.

### 6.4 Real client IP em logs

Após cutover, `X-Real-IP` que Caddy logga será IP do Cloudflare edge, não
do cliente. Caddy precisa confiar em CF e usar `CF-Connecting-IP`:

```caddyfile
{
  servers {
    trusted_proxies static <CF_IPV4_LIST> <CF_IPV6_LIST>
    client_ip_headers CF-Connecting-IP
  }
}
```

Script pra atualizar trusted_proxies semanalmente (CF muda ranges 1-2x/ano):

```bash
#!/bin/bash
# /usr/local/bin/update-caddy-cf-ranges.sh
set -euo pipefail
CONF=/etc/caddy/cloudflare-ranges.conf
TMP=$(mktemp)
{
  echo "# Auto-generated $(date -u +%FT%TZ)"
  curl -fsS https://www.cloudflare.com/ips-v4
  curl -fsS https://www.cloudflare.com/ips-v6
} > "$TMP"
if ! cmp -s "$TMP" "$CONF"; then
  mv "$TMP" "$CONF"
  systemctl reload caddy
fi
```

Systemd timer semanal opcional.

### 6.5 Rollback Phase 4

- Reverter AOP no Caddyfile (comentar `client_auth` block).
- `iptables-restore < /root/iptables.pre-cf-lockdown.bak`
- `systemctl reload caddy`

---

## 7. Phase 5 — DNS cutover (Day 4, JANELA DE MANUTENÇÃO)

> **Janela:** 02:00–06:00 BRT terça/quarta. Tráfego histórico mais baixo
> (vide Grafana baseline). Comunicar 48h antes via banner storefront +
> email pros admins de loja.

### 7.1 Pré-cutover (24h antes)

```bash
# Reduzir TTL de TODOS os records pra 60s no registrar atual.
# Acelera rollback caso precise.
# (Comando depende do registrar — Registro.br, GoDaddy, Cloudflare Registrar,
# etc. Documentar UI específica.)
```

### 7.2 Pré-flight checklist (15 min antes da janela)

- [ ] Status page atualizada → "scheduled maintenance".
- [ ] Slack ops channel: "Iniciando cutover Cloudflare em 15min."
- [ ] SSH session ativa em `root@62.238.41.231` (não fechar até T+4h).
- [ ] Tail aberto: `journalctl -u caddy -f` em outra session.
- [ ] Snapshot final de DNS atual capturado.
- [ ] Cloudflare API token testado (`curl` smoke contra `/zones`).
- [ ] Stripe Dashboard aberto pra monitor webhook delivery.

### 7.3 Cutover steps

#### Step 1 — flip records pra orange cloud (proxied) no Cloudflare

Via dashboard ou API:
```bash
# Listar records
curl -fsS -H "Authorization: Bearer $CF_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" | jq

# Pra cada record web (www, api), flip proxied=true
curl -fsS -X PATCH -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -d '{"proxied": true}'
```

Records que **devem ficar gray-cloud** (não proxied):
- `obs.viralefy.com` — Grafana, IP allowlist próprio
- MX records — Cloudflare não proxia email
- TXT records — SPF/DKIM/DMARC, nunca proxied
- Qualquer hostname interno SSH

#### Step 2 — change nameservers no registrar

No registrar do `viralefy.com`:
- Remover NS atuais.
- Adicionar os 2 nameservers que Cloudflare designou (ex: `aria.ns.cloudflare.com`
  e `roger.ns.cloudflare.com` — Cloudflare gera par único por conta).
- Salvar.

#### Step 3 — validar propagação

```bash
# Propagação típica .com: 15min–2h. Continuar até resolver via 3+ resolvers públicos.
for resolver in 1.1.1.1 8.8.8.8 9.9.9.9 208.67.222.222; do
  echo "=== $resolver ==="
  dig @"$resolver" +short NS viralefy.com
  dig @"$resolver" +short www.viralefy.com
  dig @"$resolver" +short api.viralefy.com
done
```

Critério OK: NS aponta pra `*.ns.cloudflare.com` em pelo menos 3/4 resolvers
e A records resolvem pra IPs CF (104.x ou 172.67.x).

#### Step 4 — smoke E2E externo

```bash
# Da workstation, NÃO da VPS (evita resolve via cache local).
curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" https://www.viralefy.com/
curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" https://api.viralefy.com/v1/plans
curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" https://api.viralefy.com/v1/categories

# OPTIONS preflight (CORS Caddy → CF passthrough)
curl -sS -o /dev/null -w "%{http_code}\n" -X OPTIONS \
  -H "Origin: https://www.viralefy.com" \
  -H "Access-Control-Request-Method: POST" \
  https://api.viralefy.com/v1/auth/user/login

# Login real
curl -sS -X POST https://api.viralefy.com/v1/auth/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"smoke@viralefy.com","password":"..."}'

# Stripe webhook simulado (CLI Stripe)
stripe trigger payment_intent.succeeded
# Verificar entrega em https://dashboard.stripe.com/webhooks
```

Critério OK:
- 200 em todos os GETs públicos.
- 204 no OPTIONS preflight com Access-Control-Allow-Origin populado.
- 200 ou 401 no login (não 5xx, não timeout).
- Webhook entregue dentro de 30s.

#### Step 5 — monitorar 30min com tail

```bash
# Em paralelo:
journalctl -u caddy -f | grep -E "(5[0-9]{2}|error)"
# E:
ssh root@62.238.41.231 'tail -f /var/log/caddy-waf/audit.log'
```

Critério OK: error rate Grafana < 1% por 30min consecutivos.

### 7.4 Rollback Phase 5 (decisão até T+1h)

**Critérios pra rollback imediato:**
- Error rate 5xx > 5% por 5min.
- p99 latência > 2x baseline por 5min.
- Webhook Stripe failing > 10% das deliveries.
- Auth/checkout falhando E2E em mais de 1 região.

**Procedimento (ETA propagação: 15min–4h dependendo do registrar):**
1. No registrar: restaurar NS originais (capturados em `dns-current.txt`).
2. Cloudflare dashboard → pause zone (mantém config, mas para de servir).
3. Comunicar canal ops.
4. Aguardar propagação reversa.
5. Confirmar `dig` resolvendo pros NS antigos.
6. Post-mortem obrigatório dentro de 48h.

---

## 8. Phase 6 — Coraza disable + monitor (Day 5+, gradual)

> **Não desligar Coraza imediatamente após cutover.** Manter defense in depth
> por 14 dias enquanto observamos cobertura Cloudflare.

### 8.1 T+0 (logo após cutover): Coraza permanece On

Coraza continua bloqueando. Cloudflare também bloqueia upstream. Double-WAF
gera latência extra (~2-5ms) mas é seguro.

### 8.2 T+14d: flip Coraza pra DetectionOnly

```bash
ssh root@62.238.41.231
sed -i 's/^SecRuleEngine On/SecRuleEngine DetectionOnly/' /etc/caddy/coraza/coraza.conf
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

Monitorar 14 dias adicionais. Audit log deve mostrar matches que Cloudflare
JÁ bloqueou (= cobertura redundante OK).

### 8.3 T+30d: remover Coraza do Caddyfile

Comentar bloco `coraza_waf {}` em `api.viralefy.com`. Validar, reload.

### 8.4 T+45d: remover plugin e configs

```bash
# Remover plugin Caddy
caddy remove-package github.com/corazawaf/coraza-caddy/v2
# Limpar
rm -rf /etc/caddy/coraza
rm -rf /var/log/caddy-waf
```

Liberação esperada: ~100 MB RAM, ~5% CPU em pico.

### 8.5 Rollback Phase 6

Qualquer step desta phase é reversível pelo passo anterior:
- 8.2 → mudar back pra `On`, reload.
- 8.3 → uncomment bloco, reload.
- 8.4 → reinstalar plugin (`caddy add-package ...`).

---

## 9. Cost comparison honesto

### Status atual (Caddy+Coraza)

| Item | Custo |
|---|---|
| Hardware (Coraza overhead) | ~100 MB RAM + ~5% CPU pico de 1 vCPU |
| Operator time (custom rules, debug FPs) | ~8–10 h/mês (estimativa post-soak) |
| Cash out | US$ 0 |
| Custo total ano (assumindo dev cost US$60/h) | ~US$ 6.000 (~R$ 33k) |

### Pós-migration (Cloudflare Business)

| Item | Custo |
|---|---|
| Plano Cloudflare Business | US$ 200/mês = **US$ 2.400/ano** |
| Operator time (managed rules + custom Cloudflare) | ~2–3 h/mês |
| Cash out | US$ 2.400/ano |
| Custo total ano (60 USD/h) | ~US$ 4.200 (~R$ 23k) |

### Benefícios não-monetários Cloudflare

- DDoS L3/L4/L7 protection (Coraza não cobre L3/L4, depende do upstream).
- CDN global (latência p95 menor em mercados fora BR — relevante pros 130
  países atendidos).
- Bot Management gerenciado (Coraza não tem bot fingerprinting).
- Argo opcional (Smart Routing) pra latência adicional ~10-15% menor.
- SOC2 + ISO27001 pra compliance enterprise no futuro.

### Riscos Cloudflare

- **Lock-in:** cache rules, page rules, workers ficam só lá. Saída custa
  re-migrar tudo (este runbook, ao contrário).
- **Latência adicional:** edge BR → origin BR adiciona ~5-15ms p50.
- **Visibilidade reduzida:** logs em CF dashboard, não em journalctl. Log
  push pra Loki é Business+ extra (~US$0.05/GB).
- **Single point of failure:** Cloudflare outage = Viralefy down. Histórico
  CF: 99.99% SLA, mas outages globais aconteceram (junho 2022, junho 2025).

### Veredito honesto

**Operator time saving (~7h/mês × US$60/h = US$420/mês) NÃO paga o plano
(US$200/mês) se o time já está dimensionado pro trabalho atual.** O ganho
real é em DDoS protection + CDN. Se Viralefy nunca sofreu DDoS L7 e p95
latência atual está dentro de SLA (vide Grafana), o gasto é discricionário.

---

## 10. Quando NÃO migrar

- **Soak Coraza ainda em DetectionOnly** (situação atual 2026-06-11). Migrar
  agora mascara problema de FP nos passwords que continuaria no Cloudflare.
- **Compliance LGPD que exija processamento no Brasil:** Cloudflare opera em
  EUA por default. Há opção Geo Key Manager (Enterprise) pra confinar TLS keys
  em BR, mas custa caro.
- **Latência crítica origin→edge.** Se p99 atual é < 50ms e SLA exige <100ms,
  margem de 50ms pode estourar com extra hop.
- **Custo cash flow.** Pre-revenue ou margem apertada, US$2.400/ano direto
  pesa.
- **Auditoria de WAF rules customizadas necessária.** Coraza permite inspecionar
  cada regra; Cloudflare Managed Ruleset é black-box (rule IDs documentados, mas
  pattern interno não).

---

## 11. Rollback plan completo (consolidado)

### Decisão rápida (T+0 a T+1h pós-cutover)

| Sintoma | Action |
|---|---|
| Error rate 5xx > 5% por 5min | **ROLLBACK Phase 5** (NS revert) |
| p99 latência > 2x baseline | **ROLLBACK Phase 5** |
| Webhook failures > 10% | **ROLLBACK Phase 5** |
| Auth/checkout E2E falha multi-region | **ROLLBACK Phase 5** |
| WAF false positive isolado | Edit rule pra `Skip`, sem rollback |
| Cache servindo dado privado | **Purge cache + add Bypass rule** |

### Decisão lenta (T+1h a T+14d)

| Sintoma | Action |
|---|---|
| Coraza loggando blocks que CF não vê | Add custom rule no CF |
| Latência p95 +50ms persistente | Avaliar Argo ou rollback completo |
| Custom rule CF gerando FP organica | Edit rule, manter migration |
| Outage Cloudflare > 30min | Esperar (rollback DNS leva +). Documentar SLA hit. |

### Janelas de propagação esperadas

| Mudança | Tempo |
|---|---|
| Flip orange→gray cloud no CF (records) | ~1min |
| Rate limit rule edit no CF | ~30s |
| WAF rule edit no CF | ~30s |
| NS change no registrar (rollback DNS) | 15min – 4h dependendo TTL e registrar |
| Cache purge global CF | ~30s |
| iptables CF allowlist reverse | imediato |

---

## 12. Test plan pós-migration

### Smoke automatizado (GitHub Actions)

Reusar workflow existente (`.github/workflows/smoke-external.yml`) — só
atualizar endpoint URLs caso já não estejam apontando pra `www.` e `api.`
canônicos.

### Manual E2E (operator, no T+1h)

- [ ] Login user via storefront → sucesso.
- [ ] Checkout E2E Stripe → 200 + redirect pro success page.
- [ ] Checkout E2E PIX (AbacatePay) → QR gerado.
- [ ] Login admin + 2FA → dashboard carrega.
- [ ] Backoffice: editar plan → save → reflete em /v1/plans.
- [ ] Forgot password → email entrega (sender SMTP intocado).

### Attack simulation (smoke WAF — operator IP only)

```bash
# SQLi probe
curl "https://api.viralefy.com/v1/plans?q=1+OR+1=1--"
# Esperado: 403 ou Challenge (CF block)

# XSS probe
curl "https://api.viralefy.com/v1/plans?q=<script>alert(1)</script>"
# Esperado: 403 ou Challenge

# Path traversal
curl "https://api.viralefy.com/v1/../../etc/passwd"
# Esperado: 403 ou 404
```

### Soak 14 dias

- Grafana panel "WAF blocks per hour" — comparar volume CF vs Coraza baseline.
- Loki query `{service="caddy"} |= "5"` — error rate.
- Custom rule audit toda sexta — review false positives semanais.

---

## 13. Cloudflare-specific best practices

### 13.1 Princípios

- **WAF rules sempre em `Log` por 48h antes de promover a `Block`.** Coraza
  hoje está em DetectionOnly pela mesma razão.
- **Honeypot endpoints:** se tivermos `/wp-admin`, `/.env`, etc. configurar
  custom rule pra block + IP reputation hit. (Hoje Caddy só 404 esses).
- **Geo block:** considerar block via firewall rule pra países sem clientes
  (vide Grafana — Viralefy atende 130 países, mas 90% tráfego é BR+US+EU).
  Cuidado: Cloudflare cobra workers caso queira whitelist condicional.
- **Workers (opcional):** A/B testing geo routing, edge auth pré-validation.
  US$5/mês 10M req. Não usar nesta migration — adicionar depois se needed.
- **R2 (opcional):** substituir MinIO. CDN-native, zero egress. Migração
  separada, fora deste runbook.

### 13.2 Anti-patterns a evitar

- ❌ Ativar "Under Attack Mode" sem necessidade — força JS challenge em todo
  GET, quebra crawlers SEO + Stripe webhooks.
- ❌ Cache `Cache-Control: public` em endpoints autenticados sem Bypass rule.
- ❌ Esquecer de allowlist Stripe IPs antes do cutover → webhooks bloqueados
  por Bot Fight Mode.
- ❌ Ativar HSTS no Cloudflare E no Caddy → header duplicado, alguns clients
  rejeitam.
- ❌ Confiar em `X-Forwarded-For` ao invés de `CF-Connecting-IP` → spoofable.

---

## 14. Comandos copy-paste

### 14.1 Vars iniciais
```bash
export CF_TOKEN="<api-token-scoped>"
export CF_ZONE_ID="<zone-id>"  # de https://dash.cloudflare.com/<account>/<domain>
```

### 14.2 Verificar token

```bash
curl -fsS -H "Authorization: Bearer $CF_TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify | jq
```

### 14.3 Listar DNS records

```bash
curl -fsS -H "Authorization: Bearer $CF_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?per_page=100" \
  | jq '.result[] | {id, name, type, content, proxied, ttl}'
```

### 14.4 Criar custom WAF rule (Stripe allowlist)

```bash
curl -fsS -X POST \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/rulesets" \
  -d '{
    "name": "Skip WAF for Stripe webhooks",
    "kind": "zone",
    "phase": "http_request_firewall_custom",
    "rules": [{
      "expression": "(http.request.uri.path eq \"/v1/webhooks/stripe\")",
      "action": "skip",
      "action_parameters": {"ruleset": "current"},
      "description": "Stripe HMAC-verified payloads — skip CF managed rules"
    }]
  }'
```

### 14.5 Set rate limit em /v1/auth

```bash
curl -fsS -X POST \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/rulesets" \
  -d '{
    "name": "Rate limit auth endpoints",
    "kind": "zone",
    "phase": "http_ratelimit",
    "rules": [{
      "expression": "(http.request.uri.path contains \"/v1/auth/\" and http.request.method eq \"POST\")",
      "action": "block",
      "ratelimit": {
        "characteristics": ["ip.src"],
        "period": 900,
        "requests_per_period": 10,
        "mitigation_timeout": 3600
      }
    }]
  }'
```

### 14.6 Flip record pra proxied

```bash
# Listar primeiro (Step em 14.3), pegar RECORD_ID do www
curl -fsS -X PATCH \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
  -d '{"proxied": true}'
```

### 14.7 Purge cache

```bash
# Purge tudo (emergency)
curl -fsS -X POST \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/purge_cache" \
  -d '{"purge_everything": true}'

# Purge URL específica
curl -fsS -X POST \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/purge_cache" \
  -d '{"files": ["https://api.viralefy.com/v1/plans"]}'
```

### 14.8 Smoke test pós-cutover

```bash
#!/bin/bash
set -euo pipefail
ENDPOINTS=(
  "https://www.viralefy.com/"
  "https://www.viralefy.com/login"
  "https://api.viralefy.com/v1/plans"
  "https://api.viralefy.com/v1/categories"
  "https://api.viralefy.com/v1/currencies"
  "https://api.viralefy.com/.well-known/jwks.json"
  "https://admin.viralefy.com/"
)
PASS=0
FAIL=0
for url in "${ENDPOINTS[@]}"; do
  code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 "$url" || echo "TIMEOUT")
  if [[ "$code" =~ ^(200|301|302|401)$ ]]; then
    echo "OK   $code  $url"
    PASS=$((PASS+1))
  else
    echo "FAIL $code  $url"
    FAIL=$((FAIL+1))
  fi
done
echo
echo "Result: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

### 14.9 Compare baseline pre/post

```bash
# Latência amostra (50 req)
for i in $(seq 1 50); do
  curl -sS -o /dev/null -w "%{time_total}\n" https://api.viralefy.com/v1/plans
done | sort -n | awk '
  {a[NR]=$1}
  END {
    print "p50:", a[int(NR*0.50)]
    print "p95:", a[int(NR*0.95)]
    print "p99:", a[int(NR*0.99)]
  }
'
```

---

## 15. Checklist final pré-go-live

### Phase 0–4 (preparação, sem impacto prod)
- [ ] Snapshot `/etc/viralefy/migration-snapshot-YYYYMMDD/` capturado.
- [ ] Grafana baseline 7d exportado (latência + error rate).
- [ ] Coraza completou 30d em `SecRuleEngine On` sem regressão organica.
- [ ] Conta Cloudflare Business ativa + 2FA + token escopado.
- [ ] Zone `viralefy.com` adicionado, status "Active" (TXT verification OK).
- [ ] Todos os DNS records importados — diff `dns-current.txt` vs CF: zero.
- [ ] SSL/TLS Full (Strict) configurado.
- [ ] Managed Rules ativadas em **`Log` mode**.
- [ ] Custom rules pra exclusions Coraza criadas (Stripe, auth password,
      reviews, admin/me methods, tracking URLs) — todas em `Skip`.
- [ ] Rate limit rules criadas (auth, checkout, admin, global) — em `Block`.
- [ ] Bot Fight Mode + Stripe IPs allowlist configurados.
- [ ] Cache rules definidas — Bypass em `/v1/me`, `/v1/admin`, `/v1/auth`,
      `/v1/checkout`, `/v1/webhooks`.
- [ ] AOP cert baixado e Caddyfile preparado (não aplicado ainda).
- [ ] Script `iptables-cf-lockdown.sh` preparado (não executado ainda).
- [ ] Script `update-caddy-cf-ranges.sh` preparado.
- [ ] Caddy `trusted_proxies` + `client_ip_headers CF-Connecting-IP`
      preparado (não reloaded ainda).

### Pré-cutover (Phase 5, 24-48h antes)
- [ ] TTL de todos os records reduzido pra 60s no registrar atual.
- [ ] Banner storefront ativo informando manutenção.
- [ ] Email aos admins de loja enviado.
- [ ] Status page agendado "scheduled maintenance".
- [ ] Stakeholder approval registrado em ticket.
- [ ] Janela alinhada 02:00–06:00 BRT terça/quarta.
- [ ] Rollback rehearsado em zone de teste — operator consegue reverter NS
      em < 5min.
- [ ] On-call ops dedicado pra próximas 24h pós-cutover.

### Go-live (Phase 5, dentro da janela)
- [ ] SSH session + tail logs abertos.
- [ ] Cloudflare API smoke OK.
- [ ] Records flipped pra orange cloud.
- [ ] NS change no registrar executado.
- [ ] Propagação validada em 3+ resolvers.
- [ ] Smoke automatizado (14.8) → 0 falhas.
- [ ] Smoke manual E2E (login + checkout + webhook) → OK.
- [ ] Caddy reloaded com `trusted_proxies` CF + AOP.
- [ ] iptables CF allowlist aplicado.
- [ ] Monitoring 30min: error rate < 1%, p99 < 2x baseline.

### Pós-cutover (Phase 6, T+0 a T+45d)
- [ ] T+24h: review CF Security Events, identificar false positives.
- [ ] T+48h: promover WAF managed rules de `Log` pra `Block` (gradual).
- [ ] T+7d: review Grafana — latência p95, p99 dentro de baseline ±10%.
- [ ] T+14d: Coraza → DetectionOnly.
- [ ] T+30d: remover bloco `coraza_waf` do Caddyfile.
- [ ] T+45d: desinstalar plugin Coraza, limpar configs e logs.
- [ ] Post-mortem da migration arquivado em `viralefy_archive/`.
- [ ] CONTEXT.md atualizado refletindo nova arquitetura (CF na borda).

---

## Apêndice A — diff de complexidade

### Caddy+Coraza (hoje)

- 1 Caddyfile (~410 linhas) + 3 confs Coraza (~140 linhas exclusions).
- Plugin Caddy customizado (build).
- Audit log próprio (`/var/log/caddy-waf/audit.log`).
- Logs visíveis em journalctl direto, mesmo host.
- Updates: `caddy upgrade` + recompile plugin trimestralmente.

### Cloudflare Business (pós-migration)

- Caddyfile reduzido (~390 linhas, remove `coraza_waf` block + exclusões
  CRS, mas adiciona `trusted_proxies` + AOP client_auth).
- Coraza desinstalado.
- WAF rules em Cloudflare dashboard (state externo, versionar via Terraform
  recomendado — outra ferramenta nova).
- Logs em 2 lugares: journalctl Caddy + CF Security Events dashboard.
- Updates: Cloudflare gerencia managed rules; custom rules ficam por nossa
  conta.

### Honest assessment

**Complexidade total não muda muito** — trocamos "manter regras Coraza
localmente" por "manter regras Cloudflare + sync state via Terraform pra
não perder histórico". O ganho líquido é **DDoS + CDN + bot management**,
não simplificação operacional.

---

## Apêndice B — observações da soak Coraza (2026-06-10) relevantes

(Resumo do que `CORAZA-SOAK-STATUS.md` ensinou e que vai impactar a
migração:)

1. **Password JSON field libinjection FP** — Cloudflare não permite excluir
   campo JSON específico de uma rule. Mitigação será regra path-wide. Risco
   aceito: handler já bcrypta antes do DB; WAF não agrega proteção no
   campo.
2. **Tráfego organico zero matches reais em 24h** — confirma que paranoia 2
   é overkill pro tráfego atual. CF Managed Rules em sensitivity Medium
   deve gerar volume similar.
3. **Googlebot trafega organic** (66.249.68.x) — confirmar allowlist no Bot
   Fight Mode.
4. **62.238.41.231 é IP do prod** — vai ficar atrás de CF; lembrar de
   atualizar smoke scripts e workflows GH Actions pra não bater na origin
   direto (perdem cobertura WAF).

---

**FIM DO RUNBOOK.** Atualizar este arquivo se Coraza statesoak, plano CF
mudar de preço, ou tráfego cruzar 5M req/dia.
