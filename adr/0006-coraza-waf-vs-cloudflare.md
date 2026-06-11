# ADR-0006 — Coraza WAF on-prem em vez de Cloudflare WAF

- **Status:** accepted
- **Data:** 2026-06-11
- **Decisores:** Equipe Viralefy
- **Diretriz relacionada:** §13 (segurança pipeline), §22.3 (pentest baseline)
- **Reavaliação:** 2026-12 (semestral) ou no trigger documentado

## Contexto e Problem Statement

O pentest baseline (`PENTEST-BASELINE-2026-06-10.md`) e o LGPD baseline (`LGPD-BASELINE-2026-06-10.md`) levantam Cloudflare como alternativa natural para WAF. Diretrizes §13 não obrigam um WAF específico; obrigam scanners de pipeline e runtime hardening.

Estado atual (2026-06-11):

- **Caddy + Coraza WAF** buildado via xcaddy, rodando como reverse proxy TLS terminator.
- OWASP CRS 4.10 com SecRuleEngine On + Block real (cutover em 2026-06-10 12:20 UTC).
- Paranoia level 2, com exclusões customizadas documentadas em `CORAZA-SOAK-STATUS.md`.
- Audit log JSON ativo em `/var/log/caddy-waf/audit.log`.
- WAF block rate medido: 82.4% (14/17 attack types em pentest interno).
- `RUNBOOK-CLOUDFLARE-MIGRATION.md` (planejado) com plano caso queiramos migrar.

## Decision Drivers

- **Custo:** Coraza = grátis. Cloudflare WAF Business = US$200/mês mínimo + Bot Management = US$10/m1k req.
- **Latência:** Coraza on-VPS = ~1-3ms overhead. Cloudflare = +30-80ms edge → origin.
- **Controle:** Coraza permite custom rules em SecLang versionadas em git. Cloudflare WAF tem regras gerenciadas + custom limitadas no Business tier.
- **Egress LGPD:** Cloudflare termina TLS em edge nos EUA/EU → dados pessoais brasileiros passam por jurisdição estrangeira. Cumpre LGPD via Cloudflare DPA, mas adiciona vetor de revisão.
- **Reverse proxy single-point-of-failure:** ambos têm o mesmo problema; Coraza local pelo menos é controlável pela equipe.

## Considered Options

### Option A — Cloudflare WAF + Coraza desativado

**Prós:** DDoS protection robusto (free tier já útil), regras gerenciadas atualizadas pela Cloudflare, edge cache, anycast.
**Contras:** custo recorrente, latência adicional, LGPD/DPA, perda de visibilidade fine-grained.

### Option B — Coraza WAF (status quo)

**Prós:** zero custo recorrente, controle total, audit log local, baixa latência.
**Contras:** sem DDoS L3/L4 protection (precisa de Hetzner DDoS-Shield padrão), regras dependem de manutenção interna, sem anycast.

### Option C — Cloudflare + Coraza em camadas (defense-in-depth)

**Prós:** melhor dos dois mundos.
**Contras:** custo + complexidade dobrada, debug de qual camada bloqueou.

## Decision Outcome

**Escolhida: Option B — Coraza WAF on-prem.**

Razões:

1. **Faturamento atual não justifica US$200+/mês** em WAF gerenciado.
2. **Coraza atende §13 e pentest baseline** (block rate aceitável, audit log estruturado, custom rules versionadas).
3. **LGPD ficou mais simples** com tudo on-prem em Hetzner DE (jurisdição UE com adequacy decision para BR).
4. **Cloudflare migration runbook pronto** — se trigger acionar, migração é faseável (DNS first, depois Proxy On).

## Triggers para Reavaliação (Option A/C se torna candidata)

- DDoS sustentado em L7 > 1000 RPS por > 30min, não mitigado por rate-limit do Caddy.
- Faturamento mensal > 10x atual (US$200/mês vira ruído).
- Compliance enterprise exige WAF gerenciado certificado (SOC2, ISO 27001).
- Bot Management necessário (scrapers/credential stuffing escalando).
- Expansão multi-região exigindo anycast.

## Action items

- [x] Coraza WAF ativo com Block real.
- [x] Audit log JSON ativo.
- [x] CRS exclusions documentadas.
- [ ] Concluir `RUNBOOK-CLOUDFLARE-MIGRATION.md` com checklist de cutover (DNS → Proxy → desativa Coraza) — atualmente parcial.
- [ ] Revisão semestral: contar tentativas bloqueadas + falsos positivos para decidir manter/migrar.

## Consequences

### Positivas

- Zero custo mensal de WAF.
- Logs locais permitem análise forense detalhada.
- Custom rules ajustáveis em minutos (PR + reload do Caddy).

### Negativas

- Sem proteção DDoS L3/L4 além do que Hetzner fornece nativamente.
- Manutenção contínua de CRS exclusions (falsos positivos descobertos em produção).
- Risco se Caddy/Coraza tiverem CVE crítico — mitigado por Renovate + Govulncheck.

## Links

- Diretrizes §13, §22.3
- `viralefy_archive/CORAZA-SOAK-STATUS.md`
- `viralefy_archive/PENTEST-BASELINE-2026-06-10.md`
- `viralefy_archive/LGPD-BASELINE-2026-06-10.md`
- RUNBOOK-CLOUDFLARE-MIGRATION.md (planejado)
